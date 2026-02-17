import React, { useState, useEffect, useRef } from 'react';
import axios from 'axios';
import ReactMarkdown from 'react-markdown';
import '../ChatInterface.css';
import ProgressTracker from './ProgressTracker';
import './progress-tracker.css';

// Get API URL from runtime config (injected at container startup) or fallback to env/localhost
const getApiUrl = () => {
  if (window.RUNTIME_CONFIG && window.RUNTIME_CONFIG.API_URL && window.RUNTIME_CONFIG.API_URL !== '__API_URL__') {
    return window.RUNTIME_CONFIG.API_URL;
  }
  return process.env.REACT_APP_API_URL || 'http://localhost:8000';
};
const API_URL = getApiUrl();

// Module-level tracking to prevent duplicates across re-renders
let displayedPlanInstanceId = null;

const ChatInterface = () => {
  // Travel request state
  const [travelRequest, setTravelRequest] = useState({
    userName: '',
    preferences: '',
    durationInDays: 7,
    budget: '',
    travelDates: '',
    specialRequirements: ''
  });

  // Chat and UI state
  const [messages, setMessages] = useState([]);
  const [loading, setLoading] = useState(false);
  const [instanceId, setInstanceId] = useState(null);
  const [statusPolling, setStatusPolling] = useState(false);
  const [formSubmitted, setFormSubmitted] = useState(false);
  const [planReadyForApproval, setPlanReadyForApproval] = useState(false);
  const [planData, setPlanData] = useState(null);
  const [approvalStatus, setApprovalStatus] = useState(null);
  const [confirmationStatus, setConfirmationStatus] = useState(null);
  const [orchestrationStatus, setOrchestrationStatus] = useState(null);
  const chatHistoryRef = useRef(null);
  const planDisplayedRef = useRef(false);
  
  // Auto-scroll to the bottom of chat when new messages arrive
  useEffect(() => {
    if (chatHistoryRef.current) {
      chatHistoryRef.current.scrollTop = chatHistoryRef.current.scrollHeight;
    }
  }, [messages]);

  // Handle input changes for all form fields
  const handleInputChange = (e) => {
    const { name, value } = e.target;
    
    // Convert durationInDays to number if it's that field
    if (name === 'durationInDays') {
      setTravelRequest({
        ...travelRequest,
        [name]: parseInt(value, 10) || 1
      });
    } else {
      setTravelRequest({
        ...travelRequest,
        [name]: value
      });
    }
  };

  // Submit the travel request form
  const submitTravelRequest = async () => {
    if (!travelRequest.userName || !travelRequest.preferences) {
      alert('Please fill out your name and travel preferences at minimum.');
      return;
    }

    setLoading(true);
    setFormSubmitted(true);
    
    // Add user request to messages
    const requestSummary = `
# Travel Request Submitted

* **Name**: ${travelRequest.userName}
* **Preferences**: ${travelRequest.preferences}
* **Duration**: ${travelRequest.durationInDays} days
* **Budget**: ${travelRequest.budget}
* **Dates**: ${travelRequest.travelDates}
* **Special Requirements**: ${travelRequest.specialRequirements}
    `;
    
    setMessages([...messages, { role: 'user', content: requestSummary }]);

    try {
      // Send request to the travel planner API
      const response = await axios.post(`${API_URL}/travel-planner`, travelRequest, {
        headers: {
          'Content-Type': 'application/json'
        }
      });

      // Store the instance ID for status checking
      if (response.data && response.data.id) {
        setInstanceId(response.data.id);
        setStatusPolling(true);
        
        // Add system message
        setMessages(prevMessages => [...prevMessages, { 
          role: 'bot', 
          content: `Your travel plan request is being processed. ID: ${response.data.id}`
        }]);
      }
    } catch (error) {
      console.error('Error submitting travel request:', error);
      setMessages(prevMessages => [...prevMessages, { 
        role: 'bot', 
        content: 'Error submitting your travel request. Please try again.'
      }]);
      setFormSubmitted(false);
    } finally {
      setLoading(false);
    }
  };

  // Display travel plan when ready for approval
  const displayTravelPlanForApproval = (plan) => {
    if (!plan || !plan.Plan) return;
    
    const itinerary = plan.Plan.itinerary || {};
    const attractions = plan.Plan.attractions || [];
    const restaurants = plan.Plan.restaurants || [];
    const insiderTips = plan.Plan.insiderTips || '';
    const documentUrl = plan.documentUrl || plan.Plan.documentUrl;

    let planMessage = `# 🗺️ Your Travel Plan for ${itinerary.destinationName || 'Your Destination'}\n\n`;
    
    if (itinerary.travelDates) {
      planMessage += `**Dates**: ${itinerary.travelDates}\n`;
    }
    if (itinerary.estimatedTotalCost) {
      planMessage += `**Estimated Cost**: ${itinerary.estimatedTotalCost}\n\n`;
    }

    // Daily itinerary
    if (itinerary.dailyPlan && itinerary.dailyPlan.length > 0) {
      planMessage += `## 📅 Daily Itinerary\n\n`;
      itinerary.dailyPlan.forEach(day => {
        planMessage += `### Day ${day.Day}: ${day.Date || ''}\n`;
        if (day.Activities) {
          day.Activities.forEach(activity => {
            planMessage += `- **${activity.Time}** - ${activity.ActivityName}: ${activity.Description} *(${activity.EstimatedCost || 'Free'})*\n`;
          });
        }
        planMessage += '\n';
      });
    }

    // Attractions
    if (attractions.length > 0) {
      planMessage += `## 🎯 Top Attractions\n`;
      attractions.forEach(attr => {
        planMessage += `- **${attr.Name}**: ${attr.Description} *(${attr.EstimatedCost || 'Varies'})*\n`;
      });
      planMessage += '\n';
    }

    // Restaurants
    if (restaurants.length > 0) {
      planMessage += `## 🍽️ Restaurant Recommendations\n`;
      restaurants.forEach(rest => {
        planMessage += `- **${rest.Name}** (${rest.Cuisine || 'Various'}): ${rest.Description} - ${rest.PriceRange || ''}\n`;
      });
      planMessage += '\n';
    }

    // Insider tips
    if (insiderTips) {
      planMessage += `## 💡 Insider Tips\n${insiderTips}\n\n`;
    }

    // Document URL
    if (documentUrl) {
      planMessage += `\n📄 [View Full Travel Document](${documentUrl})\n`;
    }

    // Add both messages in a single setMessages call to avoid race conditions
    setMessages(prevMessages => {
      return [
        ...prevMessages,
        { 
          role: 'bot', 
          content: `## Your travel plan is now ready for your review!\n\nPlease review the details below and decide if you'd like to proceed with this plan.` 
        },
        { role: 'bot', content: planMessage }
      ];
    });
  };

  // Polling for status updates
  useEffect(() => {
    let intervalId;
    
    if (statusPolling && instanceId) {
      intervalId = setInterval(async () => {
        try {
          const statusResponse = await axios.get(`${API_URL}/travel-planner/status/${instanceId}`);
          const status = statusResponse.data;
          
          console.log("Status update received:", status);
          
          // The API returns step, message, progress directly (not nested in customStatus)
          // Build a customStatus object from the direct response fields
          const customStatus = {
            step: status.step,
            message: status.message,
            progress: status.progress,
            destination: status.destination,
            itinerary: status.itinerary,
            travelPlan: status.travelPlan,
            documentUrl: status.documentUrl,
            finalPlan: status.finalPlan
          };
          
          // Update the orchestration status
          setOrchestrationStatus(customStatus);
          
          console.log(`[DEBUG] Checking step: "${customStatus.step}" === "WaitingForApproval" ? ${customStatus.step === "WaitingForApproval"}`);
          
          // Check if we're at the waiting for approval step
          if (customStatus.step === "WaitingForApproval") {
              console.log(`[DEBUG] INSIDE WaitingForApproval block - instanceId: ${instanceId}, displayedPlanInstanceId: ${displayedPlanInstanceId}`);
              setLoading(false);
              setPlanReadyForApproval(true);
              setApprovalStatus("waiting");
              setStatusPolling(false); // Stop polling once we have the plan
              
              // Only display plan once per instance - use module-level tracking
              if (customStatus.travelPlan && displayedPlanInstanceId !== instanceId) {
                console.log(`[DEBUG] DISPLAYING PLAN - setting displayedPlanInstanceId to ${instanceId}`);
                displayedPlanInstanceId = instanceId; // Set immediately (sync, outside React)
                
                const completePlan = {
                  Plan: {
                    itinerary: {
                      destinationName: customStatus.destination,
                      travelDates: customStatus.travelPlan.dates,
                      estimatedTotalCost: customStatus.travelPlan.cost,
                      dailyPlan: customStatus.travelPlan.dailyPlan || []
                    },
                    attractions: customStatus.travelPlan.attractions || [],
                    restaurants: customStatus.travelPlan.restaurants || [],
                    insiderTips: customStatus.travelPlan.insiderTips || "",
                    documentUrl: customStatus.documentUrl
                  },
                  documentUrl: customStatus.documentUrl
                };
                
                setPlanData(completePlan);
                displayTravelPlanForApproval(completePlan);
              } else {
                console.log(`[DEBUG] SKIPPING - already displayed for this instance`);
              }
            }
            else if (customStatus.step === "BookingTrip") {
              setLoading(true);
              setPlanReadyForApproval(false);
              setApprovalStatus("processing");
              
              setMessages(prevMessages => {
                const hasBookingMessage = prevMessages.some(msg => 
                  msg.role === 'bot' && msg.content.includes("Booking your trip"));
                
                if (!hasBookingMessage) {
                  return [...prevMessages, { 
                    role: 'bot', 
                    content: `🎯 **Booking your trip to ${customStatus.destination}...**\n\nPlease wait while we confirm your reservation details.`
                  }];
                }
                return prevMessages;
              });
            }
          
          // Check if orchestration is completed (step === "Completed")
          if (customStatus.step === 'Completed') {
            setStatusPolling(false);
            setLoading(false);
            
            if (approvalStatus === "processing") {
              setConfirmationStatus("confirmed");
              setMessages(prevMessages => [...prevMessages, { 
                role: 'bot', 
                content: `✅ **Your trip has been booked!**\n\nYou're all set for your adventure. Check your email for confirmation details and travel documents.`
              }]);
            }
          }
          
          // Check for failure
          if (customStatus.step === 'Error' || customStatus.step === 'Failed') {
            setStatusPolling(false);
            setLoading(false);
            setMessages(prevMessages => [...prevMessages, { 
              role: 'bot', 
              content: '❌ An error occurred while processing your travel plan. Please try again.'
            }]);
          }
          
        } catch (error) {
          console.error('Error polling status:', error);
        }
      }, 2000);
    }
    
    return () => {
      if (intervalId) {
        clearInterval(intervalId);
      }
    };
  }, [statusPolling, instanceId]);

  // Start a new travel plan
  const startNewPlan = () => {
    displayedPlanInstanceId = null; // Reset module-level tracking for new plan
    planDisplayedRef.current = false; // Reset the ref for new plan
    setTravelRequest({
      userName: '',
      preferences: '',
      durationInDays: 7,
      budget: '',
      travelDates: '',
      specialRequirements: ''
    });
    setMessages([]);
    setInstanceId(null);
    setStatusPolling(false);
    setFormSubmitted(false);
    setPlanReadyForApproval(false);
    setPlanData(null);
    setApprovalStatus(null);
    setConfirmationStatus(null);
    setOrchestrationStatus(null);
    setLoading(false);
  };

  // Approve the travel plan
  const approveTravelPlan = async () => {
    if (!instanceId) return;
    
    setLoading(true);
    setApprovalStatus("processing");
    setPlanReadyForApproval(false);
    
    try {
      await axios.post(`${API_URL}/travel-planner/approve/${instanceId}`, {
        approved: true,
        comments: "Please proceed with booking this travel plan."
      }, {
        headers: {
          'Content-Type': 'application/json'
        }
      });
      
      setMessages(prevMessages => [...prevMessages, { 
        role: 'user', 
        content: '✅ **I have approved the travel plan!** Please proceed with booking.'
      }]);
      
      if (!statusPolling) {
        setStatusPolling(true);
      }
      
    } catch (error) {
      console.error('Error approving travel plan:', error);
      setApprovalStatus("waiting");
      setPlanReadyForApproval(true);
      setMessages(prevMessages => [...prevMessages, { 
        role: 'bot', 
        content: '❌ Error approving your travel plan. Please try again.'
      }]);
      setLoading(false);
    }
  };
  
  // Reject the travel plan
  const rejectTravelPlan = async () => {
    if (!instanceId) return;
    
    setLoading(true);
    setApprovalStatus("processing");
    setPlanReadyForApproval(false);
    
    try {
      await axios.post(`${API_URL}/travel-planner/approve/${instanceId}`, {
        approved: false,
        comments: "I'd like to consider other options or make changes to this plan."
      }, {
        headers: {
          'Content-Type': 'application/json'
        }
      });
      
      setMessages(prevMessages => [...prevMessages, { 
        role: 'user', 
        content: '❌ **I have rejected the travel plan** and would like to make some changes.'
      }]);
      
      if (!statusPolling) {
        setStatusPolling(true);
      }
      
    } catch (error) {
      console.error('Error rejecting travel plan:', error);
      setApprovalStatus("waiting");
      setPlanReadyForApproval(true);
      setMessages(prevMessages => [...prevMessages, { 
        role: 'bot', 
        content: '❌ Error rejecting your travel plan. Please try again.'
      }]);
      setLoading(false);
    }
  };

  return (
    <div className="page-container">
      <div className="chat-title-container">
        <h1>Welcome to the Travel Planner Assistant</h1>
        {formSubmitted && <button onClick={startNewPlan} className="new-plan-btn">Start New Plan</button>}
      </div>
      
      {!formSubmitted ? (
        <div className="travel-form-container">
          <h2>Create Your Travel Plan</h2>
          
          <div className="form-group">
            <label>Name</label>
            <input
              type="text"
              name="userName"
              value={travelRequest.userName}
              onChange={handleInputChange}
              placeholder="e.g., Nick Greenfield"
            />
          </div>
          
          <div className="form-group">
            <label>Travel Preferences</label>
            <textarea
              name="preferences"
              value={travelRequest.preferences}
              onChange={handleInputChange}
              placeholder="e.g., Looking for a family-friendly luxury vacation with activities for children..."
              rows={4}
            />
          </div>
          
          <div className="form-group">
            <label>Duration (days)</label>
            <input
              type="number"
              name="durationInDays"
              value={travelRequest.durationInDays}
              onChange={handleInputChange}
              min="1"
              max="30"
            />
          </div>
          
          <div className="form-group">
            <label>Budget</label>
            <input
              type="text"
              name="budget"
              value={travelRequest.budget}
              onChange={handleInputChange}
              placeholder="e.g., Luxury, around $10000 total"
            />
          </div>
          
          <div className="form-group">
            <label>Travel Dates</label>
            <input
              type="text"
              name="travelDates"
              value={travelRequest.travelDates}
              onChange={handleInputChange}
              placeholder="e.g., July 1-11, 2025"
            />
          </div>
          
          <div className="form-group">
            <label>Special Requirements</label>
            <textarea
              name="specialRequirements"
              value={travelRequest.specialRequirements}
              onChange={handleInputChange}
              placeholder="e.g., Need connecting rooms or a family suite. Child has peanut allergy."
              rows={2}
            />
          </div>
          
          <button 
            onClick={submitTravelRequest} 
            className="submit-btn"
            disabled={loading}
          >
            {loading ? 'Processing...' : 'Plan My Trip'}
          </button>
        </div>
      ) : (
        <div className="chat-container">
          <div ref={chatHistoryRef} className="chat-history">
            {messages.map((msg, index) => (
              <div key={index} className={`chat-message ${msg.role}`}>
                <ReactMarkdown>{msg.content}</ReactMarkdown>
              </div>
            ))}
            
            {statusPolling && !planReadyForApproval && !approvalStatus && (
              <div className="loading-container">
                {orchestrationStatus ? (
                  <ProgressTracker status={orchestrationStatus} />
                ) : (
                  <div className="loading-message">
                    Creating your personalized travel plan...
                    <br />
                    This may take a minute or two.
                  </div>
                )}
              </div>
            )}
          </div>
          
          {instanceId && planReadyForApproval && approvalStatus === "waiting" && confirmationStatus !== "confirmed" && (
            <div className="approve-section">
              <h3>Do you approve this travel plan?</h3>
              <p>If you approve, we'll proceed with booking your trip based on this plan.</p>
              <div className="approval-buttons">
                <button 
                  onClick={approveTravelPlan} 
                  className="approve-btn"
                  disabled={loading || approvalStatus === "processing"}
                >
                  Yes, Book My Trip!
                </button>
                <button 
                  onClick={rejectTravelPlan} 
                  className="reject-btn"
                  disabled={loading || approvalStatus === "processing"}
                >
                  No, I Need Changes
                </button>
              </div>
            </div>
          )}
          
          {approvalStatus === "rejected" && (
            <div className="approve-section">
              <button onClick={startNewPlan} className="new-plan-btn full-width">
                Start a New Travel Plan
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default ChatInterface;
