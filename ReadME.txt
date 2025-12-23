Install local K8s instance using minikube.
###Install Docker CE:
sudo apt install -y docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin

###Start and enable docker
sudo systemctl enable --now docker

###Verify docker(OPTIONAL)
docker --version
sudo docker run hello-world

###Run docker without sudo
sudo usermod -aG docker $USER
newgrp docker

###Insatll minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
chmod +x minikube-linux-amd64
sudo mv minikube-linux-amd64 /usr/local/bin/minikube

###start minikube
minikube start --driver=docker --memory=4000 --cpus=2
minikube start --driver=docker --memory=4096 --cpus=2 --apiserver-ips=127.0.0.1 --kubernetes-version=stable



###Verify
kubectl get nodes

K8s instance will have three Namespaces: Build, Dev and Test.
###Creating namespace
kubectl create namespace build
kubectl create namespace dev
kubectl create namespace test

###verify that namespaces exists
kubectl get namespaces

Install local GitLab instance using docker compose.

###Verify(OPTIONAL)
docker --version
docker compose version

###Create GitLab Directory Structure
mkdir GitLab && cd gitlab

###Creating a docker compose yaml file
nano docker-compose.yml
Write
services:
    gitlab:
      image: gitlab/gitlab-ce:latest
      container_name: gitlab
**    restart: always
**    hostname: gitlab.local
**    environment:
**      GITLAB_OMNIBUS_CONFIG: |
**        external_url 'http://192.168.220.128:8080'
**        gitlab_rails['gitlab_shell_ssh_port'] = 2222
**        # Set explicit advertise address
**        gitlab_rails['gitlab_workhorse_socket'] = '/var/opt/gitlab/gitlab-rails/sockets/gitlab.socket'
**    ports:**
**      - "8080:8080"**
**      - "2222:22"**
**    volumes:**
**      - ./config:/etc/gitlab
**      - ./logs:/var/log/gitlab
**      - ./data:/var/opt/gitlab
**    shm_size: '256m'

then
>> docker compose up -d
>> docker logs -f gitlab

###Goexi inside the container to retrieve GitLab password
>> docker exec -it d14665a61482 /bin/bash
then cd etc -> cd gitLab -> cat initial_password
log into your GitLab using url (http:<VM-IP>:<PORT-NUMBER>):
Use those credentials
Username: root (default)
Password: cat ./etc/gitLab/initial_root_password

Deploy on minikube Build namespace one pod for Nexus Repository OSS (installed using Terraform + Ansible)
lets start with terraform, we are going to have:
providers.tf
main.tf

###providers.tf(Kubernetes providers used here)
Configures the Kubernetes provider with the details it needs to connect to a Kubernetes cluster.
terraform {
      required_providers {
      kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.17.0"**
  }}}

provider "kubernetes" {
  config_path = "~/.kube/config"  # Uses Minikube kubeconfig
}

Setting up the Kubernetes provider so you can use Terraform to manage resources (like Pods, Deployments, Services) on your local Minikube cluster.

###main.tf(PVC → Requests storage for Nexus data , Deployment → Runs Nexus in a Pod, mounts the PVC, listens on port 8081 , Service → Exposes Nexus so you can access it via a NodePort.)
Persistent Volume Claim Purpose: Requests persistent storage for Nexus so that data persists across Pod restarts.
resource "kubernetes_persistent_volume_claim" "nexus_pvc" {
    metadata {
      name      = "nexus-pvc"
      namespace = "build"
}
    spec {
      access_modes = ["ReadWriteOnce"]
      resources {
        requests = {
          storage = "5Gi"
        }}
 }}

#Nexus Deployment purpose: Runs Nexus in a Pod inside your cluster.
resource "kubernetes_deployment" "nexus" {
    metadata {
      name      = "nexus"**
      namespace = "build"**
      labels = { app = "nexus" }**
    }**
    spec {**
      replicas = 1**
      selector { match_labels = { app = "nexus" } }**
      template {**
        metadata {**
          labels = {**
            app = "nexus"**
          }}**
        spec {**
          container {**
            name  = "nexus"**
            image = "sonatype/nexus3:latest"**
            ports { container_port = 8081 }**
            volume_mount {**
              name       = "nexus-data"**
              mount_path = "/nexus-data"**
            }}**
          volume {**
            name = "nexus-data"**
            persistent_volume_claim {**
              claim_name = kubernetes_persistent_volume_claim.nexus_pvc.metadata[0].name**
            }}**
        }}**
    }}**

# Nexus Service purpose: Exposes the Nexus Pod so you can access it from outside the cluster.
resource "kubernetes_service" "nexus" {
    metadata {**
      name      = "nexus-service"**
      namespace = "build"**
    }**
    spec {selector = { app = kubernetes_deployment.nexus.metadata[0].labels.app }**
      port {**
        port        = 8081**
        target_port = 8081**
      }**
      type = "NodePort"**
    }}**

###then:
terraform init
terraform plan (optional)
terraform apply



Ansible part:
Waits for the Nexus pod in the Build namespace to exist and be running.
Gets the Nexus Service to find its NodePort.
Prints the URL where you can access Nexus in a browser.


lets start with
hosts.yml(Inventory file):
all:
  hosts:
    minikube:
      ansible_connection: local
      ansible_python_interpreter: /home/sohayla_218/technical_Assignment/ansible/venv_ansible/bin/python
 	(use the Python that has the needed modules (ansible, kubernetes, openshift) so the playbook doesn’t fail.)

2.nexus_setup.yml(Playbook file):

- name: Configure Nexus Repository OSS on Minikube
  hosts: minikube

  tasks:

    ##Make sure that the pod is up and worrking...
    - name: Wait for Nexus Pod...
      kubernetes.core.k8s_info:
        kind: Pod
        namespace: build
        label_selectors:
          - app=nexus
      register: nexus_pods ##Save all the information about the Nexus pods
      failed_when: false
      until: >
        (nexus_pods.resources | default([]) | length) > 0 and
        (nexus_pods.resources | default([]))[0].status.phase == "Running"
      retries: 10
      delay: 5

    ##Finding the network address of nexus...
    - name: Get Nexus Service NodePort
      kubernetes.core.k8s_info:
        kind: Service
        namespace: build
        name: nexus-service
      register: nexus_service ##Save the result of this task as a variable called ""nexus_service"" so It can used later.

    ##Print the URL that open Nexus...
    - name: Print Nexus access URL
      debug:
        msg: >
          Nexus is running at:
          http://{{ lookup('pipe', 'minikube ip') }}:{{ nexus_service.resources[0].spec.ports[0].nodePort }}

you should see after running playbook successfly:
ok: [minikube] => { "msg": "Nexus is running at: http://192.168.58.2:30387\n" }

(Optional) source venv_ansible/bin/activate
ansible-playbook -i hosts.yml nexus_setup.yml

but note that 192.168.58.2 is the internal Minikube VM IP.
can't be loaded through a browser, use curl http://192.168.58.2:30387 to know if working if it returns an output then it is okay...
 

---
Deploy on minikube Dev and Test namespaces MySQL DB using Helm and You should import/execute the DB scripts in Github repository above.

###Make sure that created namespace of  dev and test are there by
kubectl get ns

###check helm version
helm version

###Add the MySQL Helm chart repositoryx
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

###Deploy MySQL in Dev namespace
 helm install mysql-dev bitnami/mysql --namespace dev --set auth.rootPassword="SWA@20038" --set auth.database="demo" --set auth.username="sohayla" --set auth.password="SWA@20038" --set primary.persistence.size=1Gi --set image.repository="bitnamilegacy/mysql" --set image.tag="8.4.5-debian-12-r0"
###Deploy MySQL in test namespace
 helm install mysql-test bitnami/mysql  --namespace test --set auth.rootPassword="SWA@20038" --set auth.database="demo" --set auth.username="sohayla" --set auth.password="SWA@20038" --set primary.persistence.size=1Gi --set image.repository="bitnamilegacy/mysql" --set image.tag="8.4.5-debian-12-r0"

###Verify that pods are running(Optional)
kubectl get pods -n dev && kubectl get pods -n test

###Port forwarding(optional)
kubectl -n dev port-forward svc/mysql-dev 3306:3306
kubectl -n test port-forward svc/mysql-test 3306:3306

###Cloning GitHub repo into my machine
git clone https://github.com/ahmedmisbah-ole/Devops-Orange.git
cd Devops-orange && cd Database

kubectl -n dev exec -i $(kubectl -n dev get pod -l app.kubernetes.io/instance=mysql-dev -o jsonpath="{.items[0].metadata.name}") -- mysql -uroot -p"SWA@20038" -e "CREATE DATABASE IF NOT EXISTS toystore;"
kubectl -n dev exec -i $(kubectl -n dev get pod -l app.kubernetes.io/instance=mysql-dev -o jsonpath="{.items[0].metadata.name}") -- mysql -uroot -p"SWA@20038" toystore < toystore-test.sql

kubectl -n test exec -i $(kubectl -n test get pod -l app.kubernetes.io/instance=mysql-test -o jsonpath="{.items[0].metadata.name}") -- mysql -uroot -p"SWA@20038" -e "CREATE DATABASE IF NOT EXISTS toystore;"
kubectl -n test exec -i $(kubectl -n test get pod -l app.kubernetes.io/instance=mysql-test -o jsonpath="{.items[0].metadata.name}") -- mysql -uroot -p"SWA@20038" toystore < toystore-test.sql

###Exec into your MySQL pod and connect to the database
kubectl -n dev exec -it $(kubectl -n dev get pod -l app.kubernetes.io/instance=mysql-dev -o jsonpath="{.items[0].metadata.name}") -- mysql -uroot -p"SWA@20038" toystore
kubectl -n test exec -it $(kubectl -n test get pod -l app.kubernetes.io/instance=mysql-test -o jsonpath="{.items[0].metadata.name}") -- mysql -uroot -p"SWA@20038" toystore
when the sql> show up , write "SHOW TABLES;" to check that everything id okay.


Create helm chart for Spring Boot application to be used in gitlab pipeline deployment, Configurations of micro-services should be handled using Config maps or secrets in K8s.

###Create a helm chart for spring boot application
helm create springboot-app
th ouptut strucute will be:
springboot-app/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── hpa.yaml
    ├── serviceaccount.yaml
    └── NOTES.txt
(Optional) Delete unwanted files like hpa.yaml , NOTES.txt , _helpers.tpl, ...
###Chart.yaml
  apiVersion: v2
  name: springboot-app
  description: Spring Boot application deployed via Helm
  type: application
  version: 0.1.0
  appVersion: "1.0"

###values.yaml
  image:
    repository: nexus-service.build.svc.cluster.local:8081/springboot-app
    tag: latest
    pullPolicy: IfNotPresent
  replicaCount: 1
  service:
    type: ClusterIP
    port: 8080
  database:
    host: mysql-dev.dev.svc.cluster.local
    name: toystore
    user: sohayla
    password: SWA@20038


###deployment.yaml
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: {{ .Release.Name }}
  spec:
    replicas: {{ .Values.replicaCount }}
    selector:
      matchLabels:
        app: {{ .Release.Name }}
    template:
      metadata:
        labels:
          app: {{ .Release.Name }}
      spec:
        containers:
          - name: springboot-app
            image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
            imagePullPolicy: {{ .Values.image.pullPolicy }}
            ports:
              - containerPort: 8080
            env:
              - name: SPRING_CONFIG_LOCATION
                value: /config/application.yml
              - name: SPRING_DATASOURCE_PASSWORD
                valueFrom:
                  secretKeyRef:
                    name: {{ .Release.Name }}-secret
                    key: DB_PASSWORD
            volumeMounts:
              - name: config-volume
                mountPath: /config
        volumes:
          - name: config-volume
            configMap:
              name: {{ .Release.Name }}-config

###service.yaml
  apiVersion: v1
  kind: Service
  metadata:
    name: {{ .Release.Name }}
  spec:
    type: {{ .Values.service.type }}
    selector:
      app: {{ .Release.Name }}
    ports:
      - port: {{ .Values.service.port }}
        targetPort: 8080
  
###secret.yaml
  apiVersion: v1
  kind: Secret
  metadata:
    name: {{ .Release.Name }}-secret
  type: Opaque
  stringData:
    DB_PASSWORD: {{ .Values.database.password }}

###configmap.yaml
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: {{ .Release.Name }}-config
  data:
    application.yml: |
      server:
        port: 8080
      spring:
        datasource:
          url: jdbc:mysql://{{ .Values.database.host }}:3306/{{ .Values.database.name }}
          username: {{ .Values.database.user }}
        jpa:
          hibernate:
            ddl-auto: none
          show-sql: true
Create a Gitlab pipeline to do the following: 
Create another GitLab pipeline job that would allow user to first choose either Dev or Test namespaces. 

###Dockerfile
FROM eclipse-temurin:17-jre
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]

###.gitlab-ci.yaml
stages:
  - build
  - package
  - deploy

build_app:
  stage: build
  image: maven:3.8.5-openjdk-17
  script:
    - echo "Cloning code..."
    - git clone https://github.com/ahmedmisbah-ole/Devops-Orange.git

    - echo "Building JAR..."
    - cd Devops-Orange/Toy0Store
    - mvn clean package -DskipTests

    # Move JAR to a clean location for the next stage
    - mkdir -p ../../target
    - cp target/*.jar ../../target/app.jar

  artifacts:
    paths:
      - target/app.jar
    expire_in: 1 hour

push_to_nexus:
  stage: package
  image: docker:24.0.7
  services:
    - name: docker:24.0.7-dind
      command:
        - "--insecure-registry=192.168.58.2:30387"
  variables:
    DOCKER_HOST: tcp://docker:2375
    DOCKER_TLS_CERTDIR: ""
  script:
    - docker info
    - echo "admin123" | docker login 192.168.58.2:30387 -u admin --password-stdin
    - docker build -t 192.168.58.2:30387/spring-boot-app:latest .
    - docker push 192.168.58.2:30387/spring-boot-app:latest

deploy_dev:
  stage: deploy
  image: dtzar/helm-kubectl:latest
  script:
    - mkdir -p ~/.kube
    - echo "PASTE_YOUR_BASE64_KUBECONFIG_STRING_HERE" | base64 -d > ~/.kube/config
    - chmod 600 ~/.kube/config

    - git clone https://github.com/ahmedmisbah-ole/Devops-Orange.git
    - helm upgrade --install spring-app ./Devops-Orange/Toy0Store/helm-chart \
        --namespace dev \
        --create-namespace \
        --set image.repository=192.168.58.2:30387/spring-boot-app \
        --set image.tag=latest
  rules:
    - when: manual

deploy_test:
  stage: deploy
  image: dtzar/helm-kubectl:latest
  script:
    - mkdir -p ~/.kube
    - echo "PASTE_YOUR_BASE64_KUBECONFIG_STRING_HERE" | base64 -d > ~/.kube/config
    - chmod 600 ~/.kube/config

    - git clone https://github.com/ahmedmisbah-ole/Devops-Orange.git
    - helm upgrade --install spring-app ./Devops-Orange/Toy0Store/helm-chart \
        --namespace test \
        --create-namespace \
        --set image.repository=192.168.58.2:30387/spring-boot-app \
        --set image.tag=latest
  rules:
    - when: manual

