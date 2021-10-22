# Running the boutique shop on Azure with AKS and a Virtual Machine

## Creating Azure infrastructure

If necessary, download and log in to the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) in a terminal.

From the root of the project, navigate to the `terraform` directory and run the following commands to create the necessary infrastructure:

```sh
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## Run cart service on a Linux VM

From your terminal, SSH into the VM using the output `linux_vm_public_name` from terraform.

```sh
ssh -i ~/.ssh/id_rsa azureuser@architect.eastus.cloudapp.azure.com
```

Inside the VM, ensure that you're at the current user's home directory. Clone the `microservices-demo` project, change to branch `ci-automation` and run the following to copy the setup script to the home directory.

```sh
git clone https://github.com/architect-team/microservices-demo.git
cd microservices-demo && git checkout ci-automation && cd ..
cp microservices-demo/src/cartservice/setup.sh .
```

Set the required environment variables for the cart service using outputs from terraform.

```sh
export REDIS_ADDR=<redis_host>
export REDIS_PASSWORD=<redis_password>
```

Run the setup script to start the cart service.

```sh
chmod 777 setup.sh && ./setup.sh
```

## Create the Architect platform

Terraform will create a kubeconfig named architect-kubeconfig in the `terraform` directory when it has completed applying the infrastructure. Use it for the command below to create the Architect platform.

```sh
architect platform:create aks -a <your_architect_account_name> --type kubernetes --kubeconfig architect-kubeconfig
```

Select the kube context when prompted, then press enter to install the platform apps. Next, create an Architect environment for the new platform with the following command:

```sh
architect env:create aks --platform aks -a <your_architect_account_name>
```

Create a file called `values.yml` in the root of the `microservices-demo` project with the following content and use terraform outputs as the values:

```yml
boutique-shop/shopping-cart*:
  cartservice_host: <cart_service_host>
  existing_redis_hostname: <redis_host>
```

From the root of the `microservices-demo` project, register the boutique shop apps with the following command:

```sh
architect register src/adservice/architect.yml -t v1 &&
architect register src/productcatalogservice/architect.yml -t v1 &&
architect register src/currencyservice/architect.yml -t v1 &&
architect register src/recommendationservice/architect.yml -t v1 &&
architect register src/shippingservice/architect.yml -t v1 &&
architect register src/paymentservice/architect.yml -t v1 &&
architect register src/emailservice/architect.yml -t v1 &&
architect register src/cartservice/architect.yml -t v1 &&
architect register src/checkoutservice/architect.yml -t v1 &&
architect register src/frontend/architect.yml -t v1
```

Then deploy the boutique shop services to your AKS cluster:

```sh
architect deploy <your_architect_account_name>/frontend -a <your_architect_account_name> -e aks -i frontend:frontend -v values.yml --auto-approve
```
