.PHONY: reconcile

# targets for interacting with flux in the cluster
reconcile:
	flux reconcile kustomization journal-team-deployment --with-source

.PHONY: generate-reference
generate-reference:
	$(if $(TARGET), , $(error TARGET is not defined))
	kubectl kustomize $(TARGET) > /tmp/kustomize-reference.txt

.PHONY: compare-reference
compare-reference:
	$(if $(TARGET), , $(error TARGET is not defined))
	kubectl kustomize $(TARGET) > /tmp/kustomize-current.txt
	diff /tmp/kustomize-reference.txt /tmp/kustomize-current.txt

# Purge a single image from the Cantaloupe cache in prod.
# Credentials are read from the iiif-api-admin-secret k8s secret (ENDPOINT_API_USERNAME / ENDPOINT_API_SECRET).
# Usage: make cantaloupe-purge-cache id="lax:100555/elife-100555-fig3-v1.tif"
.PHONY: purge-iiif-cache-item
purge-iiif-cache-item:
	$(if $(id), , $(error id is not defined. Usage: make cantaloupe-purge-cache id="lax:100555/elife-100555-fig3-v1.tif"))
	CANTALOUPE_USERNAME=$$(kubectl get secret iiif-api-admin-secret -n journal--prod -o go-template='{{index .data "ENDPOINT_API_USERNAME" | base64decode}}'); \
	CANTALOUPE_SECRET=$$(kubectl get secret iiif-api-admin-secret -n journal--prod -o go-template='{{index .data "ENDPOINT_API_SECRET" | base64decode}}'); \
	kubectl port-forward -n journal--prod deploy/cantaloupe 8182:8182 & \
	PF_PID=$$!; \
	trap "kill $$PF_PID 2>/dev/null" EXIT; \
	until nc -z localhost 8182 2>/dev/null; do sleep 0.5; done; \
	curl -f -u "$$CANTALOUPE_USERNAME:$$CANTALOUPE_SECRET" \
		-X POST \
		-H "Content-Type: application/json" \
		-d "{\"verb\": \"PurgeItemFromCache\", \"identifier\": \"$(id)\"}" \
		http://localhost:8182/tasks
