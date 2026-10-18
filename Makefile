VERSION ?= $(shell cat VERSION)
PACKAGE := kro.field.vmware.com
OUT := _out

.PHONY: version chart-version sync render validate release

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

validate: render
	kubeconform -strict -summary -ignore-missing-schemas \
		-schema-location default $(OUT)/rendered.yaml
	./test/check-rendered.sh $(OUT)/rendered.yaml

release:
	cd service && kctrl package release -y -v $(VERSION)
	cp service/carvel-artifacts/packages/$(PACKAGE)/metadata.yml kro-service.yml
	echo "---" >> kro-service.yml
	cat service/carvel-artifacts/packages/$(PACKAGE)/package.yml >> kro-service.yml
