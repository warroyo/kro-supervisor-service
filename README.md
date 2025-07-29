# KRO Supervisor Service

This supervisor service can be used to install [KRO](https://kro.run/) 


## Install

1. login into VCenter and go to the worload management->services page
2. add a new service and upload the kro-service.yml
3. add any additional values that are needed, the entire [helm chart values](https://github.com/kro-run/kro/blob/main/helm/values.yaml) for KRO are supported. 
4. add the value for `adminGroup` this should map to your vsphere admin group ex. `administrators@vsphere.local`
5. install

## Usage

Follow the docs for KRO [here](https://kro.run/docs/getting-started/deploy-a-resource-graph-definition)
## Development
 
Due to a limitation with Carvel, there is an extra file added to the templates folder within the upstream folder. this is the `ns-overlay.yml`. additionally there is a value for `namespace:` added to the `values.yml`

### Releasing

```bash
export VERSION=1.0.0
make release
```
