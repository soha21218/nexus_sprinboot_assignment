This guide explains how to set up a local Kubernetes environment using Minikube, deploy GitLab, Nexus Repository, MySQL (Dev & Test), and Spring Boot application with Terraform, Ansible, Helm, and GitLab CI/CD.

📦 Prerequisites
    Ubuntu VM
    Internet access
    sudo privileges

###Install Docker CE
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin

Start & Enable Docker
    sudo systemctl enable --now docker

Verify Docker (Optional)
    docker --version && sudo docker run hello-world

Run Docker Without sudo
    sudo usermod -aG docker $USER && newgrp docker

###Install Minikube (Local Kubernetes)
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x minikube-linux-amd64
    sudo mv minikube-linux-amd64 /usr/local/bin/minikube

Start Minikube
    minikube start --driver=docker

Verify Kubernetes
    kubectl get nodes

###Create Kubernetes Namespaces
    kubectl create namespace build
    kubectl create namespace dev
    kubectl create namespace test

Verify
    kubectl get namespaces

###Install Local GitLab Using Docker Compose
Verify Docker Compose (Optional)
    docker --version
    docker compose version

Create Directory
    mkdir gitlab && cd gitlab

docker-compose.yml
    services:
      gitlab:
        image: gitlab/gitlab-ce:latest
        container_name: gitlab
        restart: always
        hostname: gitlab.local
        environment:
          GITLAB_OMNIBUS_CONFIG: |
            external_url 'http://192.168.220.128:8088'
            gitlab_rails['gitlab_shell_ssh_port'] = 2222
        ports:
          - "8088:8088"
          - "2226:22"
        volumes:
          - ./config:/etc/gitlab
          - ./logs:/var/log/gitlab
          - ./data:/var/opt/gitlab
        shm_size: '256m'
        healthcheck:
          disable: true

Run GitLab: docker compose up -d

Check Logs (Optional)
    docker logs -f gitlab

Get GitLab Root Password
docker exec -it <container_id> /bin/bash
cat /etc/gitlab/initial_root_password

Login:
URL: http://<VM-IP>:8088
Username: root
Password: from file above

###Deploy Nexus Repository OSS (Build Namespace)
Terraform Files
providers.tf
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.17.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

main.tf
    PVC → Persistent storage
    Deployment → Nexus Pod
    Service → NodePort access

Apply Terraform
    terraform init
    terraform plan
    terraform apply

###Configure Nexus Using Ansible
    Inventory (hosts.yml)
    all:
      hosts:
        minikube:
          ansible_connection: local
          ansible_python_interpreter: /home/sohayla_218/technical_Assignment/ansible/venv_ansible/bin/python

Playbook (nexus_setup.yml)
    Waits for Nexus Pod
    Fetches NodePort
    Prints Nexus URL

Run:
    source venv_ansible/bin/activate
    ansible-playbook -i hosts.yml nexus_setup.yml

one of the expected Output -> Nexus is running at: http://192.168.58.2:30387

⚠️ Note: Minikube IP is internal.
Use: curl http://192.168.58.2:30387 -> to check if it running 

###Deploy MySQL Using Helm (Dev & Test)
Add Helm Repo
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

Deploy MySQL (Dev)
    helm install mysql-dev bitnami/mysql \
      --namespace dev \
      --set auth.rootPassword="SWA@20038" \
      --set auth.database="demo" \
      --set auth.username="sohayla" \
      --set auth.password="SWA@20038" \
      --set primary.persistence.size=1Gi \
      --set image.repository="bitnamilegacy/mysql" \
      --set image.tag="8.4.5-debian-12-r0"

Deploy MySQL (Test)
    helm install mysql-test bitnami/mysql \
      --namespace test \
      --set auth.rootPassword="SWA@20038" \
      --set auth.database="demo" \
      --set auth.username="sohayla" \
      --set auth.password="SWA@20038" \
      --set primary.persistence.size=1Gi \
      --set image.repository="bitnamilegacy/mysql" \
      --set image.tag="8.4.5-debian-12-r0"

Verify Pods
    kubectl get pods -n dev
    kubectl get pods -n test

###Import Database Scripts
git clone https://github.com/ahmedmisbah-ole/Devops-Orange.git
cd Devops-Orange/Database


Run SQL in Dev & Test:
kubectl -n dev exec -i $(kubectl -n dev get pod -l app.kubernetes.io/instance=mysql-dev -o jsonpath="{.items[0].metadata.name}") -- mysql -uroot -p"SWA@20038" -e "CREATE DATABASE IF NOT EXISTS toystore;" 
kubectl -n dev exec -i $(kubectl -n dev get pod -l app.kubernetes.io/instance=mysql-dev -o jsonpath="{.items[0].metadata.name}") -- mysql -uroot -p"SWA@20038" toystore < toystore-test.sql 
kubectl -n test exec -i $(kubectl -n test get pod -l app.kubernetes.io/instance=mysql-test -o jsonpath="{.items[0].metadata.name}") -- mysql -uroot -p"SWA@20038" -e "CREATE DATABASE IF NOT EXISTS toystore;" 
kubectl -n test exec -i $(kubectl -n test get pod -l app.kubernetes.io/instance=mysql-test -o jsonpath="{.items[0].metadata.name}") -- mysql -uroot -p"SWA@20038" toystore < toystore-test.sql 
###Exec into your MySQL pod and connect to the database 
kubectl -n dev exec -it $(kubectl -n dev get pod -l app.kubernetes.io/instance=mysql-dev -o jsonpath="{.items[0].metadata.name}") -- mysql -uroot -p"SWA@20038" toystore 
kubectl -n test exec -it $(kubectl -n test get pod -l app.kubernetes.io/instance=mysql-test -o jsonpath="{.items[0].metadata.name}") -- mysql -uroot -p"SWA@20038" toystore 
when the sql> show up , write "SHOW TABLES;" 

###Create Helm Chart for Spring Boot
helm create springboot-app

Chart Structure
springboot-app/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── configmap.yaml
    └── secret.yaml
Configuration uses ConfigMaps & Secrets.

🔟 Dockerfile (Spring Boot)
FROM eclipse-temurin:17-jdk-alpine
WORKDIR /app
COPY Devops-Orange/Toy0Store/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]

1️⃣1️⃣ GitLab CI/CD Pipeline
Features
Build JAR
Push image to Nexus
Manual deployment to Dev or Test
Helm-based deployment

.gitlab-ci.yml

(As provided in your configuration)

deploy_dev → manual

deploy_test → manual

User chooses environment from GitLab UI


