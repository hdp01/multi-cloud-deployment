#!/bin/bash

AWS_URL=$(kubectl --context=arn:aws:eks:us-east-1:263364810108:cluster/multi-cloud-eks get svc python-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

AZ_IP=$(kubectl --context=multi-cloud-aks get svc python-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

NGINX_IP="3.239.200.208"

if [ -z "$AWS_URL" ] || [ -z "$AZ_IP" ]; then
    echo "ERROR: Could not fetch cloud endpoints."
    echo "AWS URL: [$AWS_URL]"
    echo "Azure IP: [$AZ_IP]"
    echo "Please wait 60 seconds for the Load Balancers to finish provisioning and try again."
    exit 1
fi

echo "Endpoints found. Pushing configuration to $NGINX_IP..."

ssh -i ./mc-key -o StrictHostKeyChecking=no ubuntu@$NGINX_IP <<EOF
sudo bash -c "cat <<'NginxConfig' > /etc/nginx/sites-available/default
upstream my_app {
    server $AWS_URL max_fails=3 fail_timeout=30s;
    server $AZ_IP max_fails=3 fail_timeout=30s;
}

server {
    listen 80;
    location / {
        proxy_pass http://my_app;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
    }
}
NginxConfig"

# Check if the config is valid before restarting
if sudo nginx -t; then
    sudo systemctl restart nginx
    echo "Nginx restarted successfully!"
else
    echo "NGINX CONFIG ERROR: See output above."
fi
EOF