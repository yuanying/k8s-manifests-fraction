KUBEVIRT_VER := v0.57.1
CDI_VER := v1.55.0

all: download-kubevirt download-cdi

download-kubevirt:
	curl -Lo kubevirt/operator.yaml https://github.com/kubevirt/kubevirt/releases/download/$(KUBEVIRT_VER)/kubevirt-operator.yaml
	curl -Lo kubevirt/cr.yaml https://github.com/kubevirt/kubevirt/releases/download/$(KUBEVIRT_VER)/kubevirt-cr.yaml

download-cdi:
	curl -Lo cdi/operator.yaml https://github.com/kubevirt/containerized-data-importer/releases/download/$(CDI_VER)/cdi-operator.yaml
	curl -Lo cdi/cr.yaml https://github.com/kubevirt/containerized-data-importer/releases/download/$(CDI_VER)/cdi-cr.yaml
