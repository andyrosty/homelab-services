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
