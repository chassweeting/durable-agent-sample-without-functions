#!/bin/sh
# Inject runtime environment variables into config.js
API_URL=${REACT_APP_API_URL:-http://localhost:8000}

cat > /usr/share/nginx/html/config.js << EOF
window.RUNTIME_CONFIG = {
  API_URL: "${API_URL}"
};
EOF

echo "Injected API_URL: ${API_URL}"
