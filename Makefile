# Build/Release package configuration
release:
	cd service && kctrl package release -y -v ${VERSION}
	cd service && cp carvel-artifacts/packages/kro.fling.vsphere.vmware.com/metadata.yml ../kro-service.yml
	echo "\n---" >> kro-service.yml
	cd service && cat carvel-artifacts/packages/kro.fling.vsphere.vmware.com/package.yml >> ../kro-service.yml