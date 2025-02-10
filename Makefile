.PHONY: reconcile

# targets for interacting with flux in the cluster
reconcile:
	flux reconcile kustomization journal-team-deployment --with-source

.PHONY: generate-reference
generate-reference:
	kubectl kustomize $(TARGET) > /tmp/kustomize-reference.txt

.PHONY: compare-reference
compare-reference:
	kubectl kustomize $(TARGET) > /tmp/kustomize-current.txt
	diff /tmp/kustomize-reference.txt /tmp/kustomize-current.txt
