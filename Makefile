.PHONY: deploy status delete sync

CONTROL_NODE=andrew@192.168.50.147
REMOTE_DIR=/tmp/homelab-services

sync:
	ssh $(CONTROL_NODE) "rm -rf $(REMOTE_DIR) && mkdir -p $(REMOTE_DIR)"
	scp -r apps clusters $(CONTROL_NODE):$(REMOTE_DIR)/

deploy: sync
	ssh $(CONTROL_NODE) "sudo k3s kubectl apply -k $(REMOTE_DIR)/clusters/homelab"

status:
	ssh $(CONTROL_NODE) "sudo k3s kubectl get nodes -o wide && sudo k3s kubectl get pods -A -o wide && sudo k3s kubectl get svc -A"

delete:
	ssh $(CONTROL_NODE) "sudo k3s kubectl delete -k $(REMOTE_DIR)/clusters/homelab --ignore-not-found=true"

install-ingress:
	ssh $(CONTROL_NODE) "rm -rf /tmp/kubernetes-ingress && git clone --depth 1 --branch v5.4.3 https://github.com/nginx/kubernetes-ingress.git /tmp/kubernetes-ingress"
	ssh $(CONTROL_NODE) "cd /tmp/kubernetes-ingress && sudo k3s kubectl apply -f deployments/common/ns-and-sa.yaml"
	ssh $(CONTROL_NODE) "cd /tmp/kubernetes-ingress && sudo k3s kubectl apply -f deployments/rbac/rbac.yaml"
	ssh $(CONTROL_NODE) "cd /tmp/kubernetes-ingress && sudo k3s kubectl apply -f deployments/common/nginx-config.yaml"
	ssh $(CONTROL_NODE) "cd /tmp/kubernetes-ingress && sudo k3s kubectl apply -f deployments/common/ingress-class.yaml"
	ssh $(CONTROL_NODE) "sudo k3s kubectl apply -f https://raw.githubusercontent.com/nginx/kubernetes-ingress/v5.4.3/deploy/crds.yaml"
	ssh $(CONTROL_NODE) "cd /tmp/kubernetes-ingress && sudo k3s kubectl apply -f deployments/deployment/nginx-ingress.yaml"
	ssh $(CONTROL_NODE) "cd /tmp/kubernetes-ingress && sudo k3s kubectl apply -f deployments/service/nodeport.yaml"
	ssh $(CONTROL_NODE) "sudo k3s kubectl rollout status deployment/nginx-ingress -n nginx-ingress --timeout=180s"
	ssh $(CONTROL_NODE) "sudo k3s kubectl get pods -n nginx-ingress -o wide && sudo k3s kubectl get svc -n nginx-ingress"
