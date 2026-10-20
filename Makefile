VERSION ?= $(shell cat VERSION)
PACKAGE := kro.field.vmware.com
OUT := _out

.PHONY: version chart-version sync render validate release test-package install-supervisor-service smoke-test smoke-test-multitenancy

version:
	@echo $(VERSION)

# Upstream chart version pinned in service/vendir.yml.
chart-version:
	@yq '.directories[0].contents[0].helmChart.version' service/vendir.yml

# Fetch the upstream chart and lay the Supervisor overrides on top of it.
sync:
	cd service && vendir sync
	yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
		service/upstream/values.yaml service/supervisor-overrides/supervisor-values.yaml \
		> service/upstream/values.merged.yaml
	mv service/upstream/values.merged.yaml service/upstream/values.yaml
	cp -r service/supervisor-overrides/templates/. service/upstream/templates/

# Render the package the way kapp-controller does: helm template into the
# placeholder namespace, then ytt over the output. Run `make sync` first.
render:
	mkdir -p $(OUT)
	helm template kro service/upstream --namespace kro --include-crds \
		-f test/values-supervisor.yaml \
		| ytt --ignore-unknown-comments -f - > $(OUT)/rendered.yaml
	helm template kro service/upstream --namespace kro --include-crds \
		-f test/values-supervisor.yaml -f test/values-multitenancy.yaml \
		| ytt --ignore-unknown-comments -f - > $(OUT)/rendered-multitenancy.yaml

validate: render
	kubeconform -strict -summary -ignore-missing-schemas \
		-schema-location default $(OUT)/rendered.yaml $(OUT)/rendered-multitenancy.yaml
	./test/check-rendered.sh $(OUT)/rendered.yaml
	./test/check-rendered-multitenancy.sh $(OUT)/rendered-multitenancy.yaml

release:
	cd service && kctrl package release -y -v $(VERSION)
	cp service/carvel-artifacts/packages/$(PACKAGE)/metadata.yml kro-service.yml
	echo "---" >> kro-service.yml
	cat service/carvel-artifacts/packages/$(PACKAGE)/package.yml >> kro-service.yml

# Build and push a test package without touching the committed release files.
# Writes $(OUT)/kro-service.yml. Use a pre-release VERSION, for example
# make test-package VERSION=1.2.0-rc.1, then install it with
# SERVICE_YAML=$(OUT)/kro-service.yml make install-supervisor-service.
test-package:
	mkdir -p $(OUT)
	rm -rf $(OUT)/release-backup && mkdir -p $(OUT)/release-backup
	cp -r kro-service.yml service/package-build.yml service/carvel-artifacts $(OUT)/release-backup/
	cd service && kctrl package release -y -v $(VERSION); status=$$?; cd ..; \
	cp service/carvel-artifacts/packages/$(PACKAGE)/metadata.yml $(OUT)/kro-service.yml; \
	echo "---" >> $(OUT)/kro-service.yml; \
	cat service/carvel-artifacts/packages/$(PACKAGE)/package.yml >> $(OUT)/kro-service.yml; \
	rm -rf service/carvel-artifacts; \
	cp -r $(OUT)/release-backup/kro-service.yml .; \
	cp -r $(OUT)/release-backup/package-build.yml service/; \
	cp -r $(OUT)/release-backup/carvel-artifacts service/; \
	exit $$status

# Register and install (or upgrade) kro-service.yml on a Supervisor through the
# vCenter API. Needs VC_HOST, VC_USER and VC_PASSWORD_FILE (or VC_PASSWORD).
install-supervisor-service:
	./test/install-supervisor-service.sh

# RGD plus instance round trip on a live Supervisor. NAMESPACE is a Supervisor Namespace.
smoke-test:
	./test/smoke/run.sh $(NAMESPACE)

# Multitenancy checks on a live Supervisor. Needs the KRO_* contexts described
# in test/smoke/multitenancy.sh.
smoke-test-multitenancy:
	./test/smoke/multitenancy.sh
