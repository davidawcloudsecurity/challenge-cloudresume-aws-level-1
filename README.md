# challenge-cloudresume-aws-level-1
How To Setup A 3 Tier Web Architecture With NGINX, Wordpress and MSSQL Using EC2 Instance

## Setup aliases for shortcuts
```ruby
alias tf="terraform"; alias tfa="terraform apply --auto-approve"; alias tfd="terraform destroy --auto-approve"; alias tfm="terraform init; terraform fmt; terraform validate; terraform plan"
```
## Run this if running at cloudshell
How to install terraform - https://developer.hashicorp.com/terraform/install
```ruby
sudo yum install -y yum-utils shadow-utils; sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo; sudo yum -y install terraform; terraform init
```
