# Deploy a Web server to AWS

The goal of this repository is to implement a basic web server, deploy it on AWS and describe the process along the way.

Here are the big steps that have been taken in this repository
1. [Deploying for a first time](#deploying-for-a-first-time),
2. [Trying AWS Fargate instead of EC2 instances](#trying-aws-fargate-instead-of-ec2-instances),
3. [Infrastructure as code using Terraform](#infrastructure-as-code-using-terraform).

## Service description

This is a simple webserver exposing one healthcheck route `GET /health`. The associated handler will check the health of a connected `postgres` database and answer a status `200` response with a JSON body `{ ok: true, services: { database: true } }`.

## Deploying for a first time

Here is the list of steps that have been taken when developing and deploying the service.

1. [First iteration of the service](#1-first-iteration-of-the-service),
2. [Setup Dockerfile](#2-setup-dockerfile),
3. [Before starting the deployment process](#3-before-starting-the-deployment-process),
4. [Account creation and AWS setup](#4-account-creation-and-aws-setup),
5. [Push the docker image to AWS ECR](#5-push-the-docker-image-to-aws-ecr),
6. [Switch to AWS ECS](#6-switch-to-aws-ecs),
7. [Creating an ECS cluster](#7-creating-an-ecs-cluster),
8. [Creating a task definition](#8-creating-a-task-definition),
9. [Running my Task](#9-running-my-task),
10. [Exposing my container to the internet](#10-exposing-my-container-to-the-internet),
11. [Success](#11-success),
12. [Preparing second iteration: adding a database in all that](#12-preparing-second-iteration-adding-a-database-in-all-that)
13. [Create a database](#13-create-a-database),
14. [Connecting the app to the database](#14-connecting-the-app-to-the-database),

### 1. First iteration of the service

The web server is developed with basic capabilities:
- `GET /health` route which answers a status `200` and JSON data `{ ok: true }`,
- global timeout controlled by env var `GLOBAL_TIMEOUT`,
- server listening on port controlled by env var `PORT` (default to `3000`),
- graceful shutdown.

At this stage `PORT=3002 cargo run` should start the server and `curl http://localhost:3002/health` should give back a 200 status response with `{ ok: true }` as body.

### 2. Setup Dockerfile

The service is running, now we need to prepare it for deployment. [Docker](https://www.docker.com/) is a very powerful and well known way of "containerizing" your application in order to later deploy your containers in the cloud.

I am not the biggest Docker expert so I went checking online on how to create a proper `Dockefile` for a rust-based webserver, I ended up on the [Rust language guide by Docker](https://docs.docker.com/language/rust/build-images/). I did not know that `Docker` exposes now a `docker init` script in order to setup the all things Docker. So I went with it
```console
docker init
```
I used all the default options and it created a `.dockerignore`, a `compose.yml`, a `Dockerfile` and a `README.Docker.md`. All the files contain explanatory comments wich is greatly appreciated.

During the creation process of the Dockerfile, I set that the listening port was `3000` and as a consequence, the `EXPOSE 3000` command has been added in the Dockerfile. **However**, I don't really know in advance which `port` I will use since I setup the exposed `port` in my service as controlled by the `PORT` env variable. The `EXPOSE` cmd is actually not publishing the port and acts as a documentation between the Dockerfile and the developer running it, as [the documentation](https://docs.docker.com/engine/reference/builder/#expose) explains. Therefore, I remove the `EXPOSE 3000` line in my Dockerfile and I will handle the exposed `PORT` when running my container.

I modify the `compose.yml` as an example of it
``` yaml
services:
  server:
    build:
      context: .
      target: final
    ports:
      - 3002:3001
    environment:
      - PORT=3001
```
My `PORT` env variable is set to 3001, so the container will listen on PORT 3001, and I map the container port to the "public" (outside of `Docker`) PORT 3002. See more about ports in the [Docker documentation](https://docs.docker.com/network/#published-ports).

At this stage, I can run the docker compose
```console
docker compose up
```
and query my healthcheck route on PORT 3002
```console
curl http://localhost:3002
```

It is also possible to run the dockerized app without `docker compose`. First we create the `Docker image` using the freshly defined Dockerfile
```console
docker build -t my-app .
```
And then run a `Docker container` based on this `Docker image`:
```console
docker run --publish 3002:3001 --env PORT=3001 my-app
```

### 3. Before starting the deployment process

From now on, the goal will be to deploy the application to [Amazon AWS](https://aws.amazon.com/).

I started this section by following this [video guide](https://www.youtube.com/watch?v=jCHOsMPbcV0) on how to setup an AWS account and the AWS CLI.

Then I will start simple and dirty by following [this youtube video guide](https://www.youtube.com/watch?v=zs3tyVgiBQQ). With this, I'll direclty use the AWS interface in order to perform the deployment. I will not put screenshots of the steps as it will never be better than what it is in the video.

However, I'll try to understand and explain as best as I can the different steps and the various notions in it.

Way later on, the goal will be to perform deployment using code and to integrate the deployment directly in the CI.

### 4. Account creation and AWS setup

Here is a [video guide](https://www.youtube.com/watch?v=jCHOsMPbcV0) that one can refer to for this step.

I have a personal AWS account, my credentials are representing the so-called `root user` for this AWS account. This is actually strongly advised (by AWS) to not use the root user for the every day tasks on AWS, see more details [here](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_root-user.html).

Instead of using the root user, I create a new user using the [IAM service](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html) (AWS Identity and Access Management) with only the access I need for my task.

I created a user without any permissions policies because I still don't know which permissions I am gonna need. I also created an `access key` for this account as I will need it to setup my AWS CLI. For this I created an associated `profile` named `aws-guide` by directly modifying my files `~/.aws/config` and `~/.aws/credentials`. A more beginner friendly way would be to use the `aws configure` CLI method.

From now, I will use this newly created account (with no permissions for the moment) to perform the tasks. Along this guide, I will use the `root user` of my AWS account in order to add to this progammatic account the permissions I need.

### 5. Push the docker image to AWS ECR

I am following [the first part of this youtube video guide](https://www.youtube.com/watch?v=zs3tyVgiBQQ) for this step.

On step 2, I was able to create a Docker `image` of my app. This image was stored in my machine and I can access it using `docker images`.

From this Docker image, I was able to run locally a Docker container by specifying the exposed port and then access my application.

Now we want to deploy this dockerized application using the AWS cloud. AWS will use the Docker image to do that, but first I need to make this image accessible on AWS by pushing my Docker image to AWS.

For this, AWS has a particular service known as [AWS Elastic Container Registry (or ECR)](https://aws.amazon.com/ecr/). It will allow me to store my Docker images and make them available from the other AWS services (in particular the one I'll use later on to deploy it).

First I'll need to login to AWS ECR with my account (not the root user). With that, my Docker is connected to the remote AWS ECR repository where I'll be able to push my Docker image later on.
```console
aws ecr get-login-password --region <My AWS region> --profile <My profile, omit if using default> | docker login --username AWS --password-stdin <My AWS account ID>.dkr.ecr.<My AWS region>.amazonaws.com
```
I actually got an error of the type `not authorized to perform: ecr:GetAuthorizationToken on resource: * because no identity-based policy allows the ecr:GetAuthorizationToken action` as my account lacks the needed permissions. So I'll use my root user to add to user a permission policiy with full access to `ECR` (`ecr:*`). In a real setup, I would try to not give that much power to this user but restrict to the needed permissions, I took a shortcut in this case.

Running again the command, I have a `Login Succeeded`.

Now that I have access to ECR, I first need to create a repository where I'll push the docker images for my application. I don't have any repositories for now as I can see by running
```console
aws ecr describe-repositories --profile <My profile, omit if using default>
```

I'll create a new repository named `aws-guide-repo`
```console
aws ecr create-repository --repository-name aws-guide-repo --profile <My profile, omit if using default>
```

I am now able to see my repository using the `describe-repositories` above.

Now that I have my repository, I can push my Docker image to it, for this I will build locally my Docker image first
```console
docker build --platform=linux/amd64 -t aws-guide-app .
```

PS: the `--platform=linux/amd64` is explained later on.

With that I created locally the Docker image `aws-guide-app` with the (default) tag `latest`.

I am pushing the image to a private registry, as such, the image name and tag must follow the convention `<Registry host name>:<image tag>`. In my case, the registry host name is given by `<My AWS registry URL>/<My ECR repository name>` which becomes `<My AWS account ID>.dkr.ecr.<My AWS region>.amazonaws.com/aws-guide-repo`. I will keep the tag as `latest` in my case as I don't need specific tag. See more details about `docker tag` in the [associated Docker section](https://docs.docker.com/engine/reference/commandline/image_tag/) and in the [private registry dedicated part](https://docs.docker.com/engine/reference/commandline/image_tag/#tag-an-image-for-a-private-registry).
```console
docker tag aws-guide-app:latest <My AWS account ID>.dkr.ecr.<My AWS region>.amazonaws.com/aws-guide-repo:latest
```

And I am finally able to upload it to the ECR repository
```console
docker push <My AWS Account ID>.dkr.ecr.<My AWS region>.amazonaws.com/aws-guide-repo:latest
```

I am now able to see my image on my repository
```console
aws ecr describe-images --repository-name aws-guide-repo --profile <My profile, omit if using default>
```

### 6. Switch to AWS ECS

I am following [the second part of this youtube video guide](https://www.youtube.com/watch?v=zs3tyVgiBQQ) for this step.

I'll cheat here and follow the video by using my root user in the AWS Console application. It would not be the way to do it in professional environments but I hope I can do it properly with a dedicated and non root account later on when improving the setup.

Now I'm done with the AWS ECR, I have my Docker image available in AWS. My goal is now to use it for a deployment.

For that I meet [AWS Elastic Container Service or ECS](https://aws.amazon.com/ecs/).

From the docs
> Amazon Elastic Container Service (ECS) is a fully managed container orchestration service that helps you to more efficiently deploy, manage, and scale containerized applications.

Since I have my containerized application, ECS seems the thing I need.

While browsing a bit, the [getting started](https://aws.amazon.com/ecs/getting-started) on ECS is full of tutorials, seems promising for a later time.

It seems that there is a lot of things in ECS, different tools or solutions in order to best achieve different goals. I am not yet ready to parse every solutions, I'll start with the one in the video and try to understand what it is first.

### 7. Creating an ECS cluster

I am following [the second part of this youtube video guide](https://www.youtube.com/watch?v=zs3tyVgiBQQ) for this step.

So I did go to the ECS part on the AWS Console, first thing I need is to create a `cluster`.

I'm looking to understand what a cluster is first. From the [developer guide page about cluster](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/clusters.html), it says that a cluster is first *a logic grouping of tasks and services*, I don't exactly know what a *task* or a *service* is for the moment so I'll skip this part for now.

Additionally, the doc says that it is additionally the *infrastructure capacity*, I understand it as the hardware on which we're gonna run our code. It can be a combination of:
- on premises virtual machines or servers: I'm not interested in that,
- Amazon EC2 instances in the AWS Cloud: the instances that AWS provide,
- Serveless with AWS Fargate in the AWS Cloud: I don't exactly know what Fargate is but I understand it as an abstraction over EC2 instances in order to not have to manage directly a fleet of EC2. It looks interesting but we're gonna follow the video and start with the good old' EC2 instances.

Actually, I got a better description from the cluster creation page
![cluster infrastructure components](/images/Screenshot%202024-02-15%20at%2021.25.23.png)

A cluster consists also of `The network (VPC and subnet) where your tasks and services run`. Since this is related to tasks and services, we're gonna explore this a bit later.

Finally, a cluster consists also of *an optional namespace* and a *monitoring option*. It seems less important to me for now.


**Let's now create the cluster.**

First thing is to choose a name, I chose `AwsGuideCluster`.

#### Selecting infrastructure

When chosing *infrastructure*, I disable `AWS Fargate (serverless)` and I enable `Amazon EC2 Instances` as I want to start with basic EC2 instances.

The next step is to define the `Auto Scaling Group (ASG)` for these EC2 instances. As I understand, it is the set of parameters that will define the type of EC2 instances, how many and how they are provisionned.

1. `Provision model`: I choose `On Demand` (`Spot` was the other choice) as I don't plan to have this application deployed in the long term and I will not consume a lot of compute capacity.
2. `Operating System/Architecture`: Huge list of possibilities, I am absolutely not an expert. The first choice is `Amazon Linux 2`, which have eligibility in the free plan and seems like a [good default as it is directly maintained by AWS and with no additional charge](https://aws.amazon.com/amazon-linux-2).
3. `EC2 Instance Type`: Again a huge list of possibilities. I read a quick overview of the different instances types [here](https://aws.amazon.com/blogs/aws/choosing-the-right-ec2-instance-type-for-your-application/), as I see the `micro` instances belong to the free tier and can be very small, which is fine for me. In the end, I only need to test things out so I chose a `t2.micro`. I actually [discussed a bit with Chat GPT](https://chat.openai.com/share/c8c76c08-712e-4dac-a1ba-5a521e5e55e1) about this in order to understand the differences between all the `t2`, `t3`, `t3a` or `t4g` instances.
4. `Desired capacity`: I only need one machine, so I set the minimum to `0` and the maximum to `1`.
5. I let the remaining parameters as default, i.e. unable to SSH and default root volume of 30GiB (which is the minimum anyway).


#### Networks

Now I need to choose the *Networks settings*. There are a lot of new notions here.

The first thing I need to do is to choose a `VPC`, I'll choose the default one but I'll try to understand a bit better what it is.

So `VPC` stands for `Virtual Private Cloud`, it is a virtual network in AWS dedicated to my AWS account. It isolates my resources (e.g. EC2 instances, containers, databases) from anything else. Resources within a VPC can securely communicate to each other, however, if I want my resource in my VPC to communicate with something outside from it (like the internet), I will need to do some additional work.

To each VPC is attached `subnets`. A `subnet` will be a range of IP addresses in the VPC and is necessarily living in a single `Availability Zone`. An availability zone is defined as isolated locations within a region. A resource living in a subnet will necessarily have an IP belonging to the defined range of the subnet. In my setup, I will have three subnets (minimum number recommended by AWS for production), one in each availability zone. Ideally, I would run an instance in each subnet in such a way that if an availability zone crashes, the two others would still be fine. More informations on the page about [Regions and Zones](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html) in the AWS documentation.

As an example, I am working in the `eu-west-3` (Paris, France) region because this is where I expect most of my users will be (e.g. me), and the three available subnets the default VPC offers are in `eu-west-3a`, `eu-west-3b` and `eu-west-3c` availability zones.

The next beast I need to choose is the [Security Group](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html), I'll once again choose the default one. A security group acts as a firewall for the container instances running in my VPC, as specified in the documentation: *A security group controls the traffic that is allowed to reach and leave the resources that it is associated with.*. The extremes would be to have a security group which would block or allow all the inbound and outbound traffic to the instances in this security group. In the case of the [default security group](https://docs.aws.amazon.com/vpc/latest/userguide/default-security-group.html), it will allow inbound traffic from any other instance assigned to this security group and it will allow all outbound traffic to any address. This choice is only for the default security group of my VPC, I can then add, and it is encouraged to so, other security groups tailored to my particular needs. In my case of course, I don't need much and the default security group seems good.

The last option I need to the `networks` part is the `Auto-assign public IP`. If I turn this on, my EC2 instances will have a public IP address automatically assigned. While I don't think this is what I would like for a serious setup, I will turn on this on as I will need to access what is running on my EC2 instance later on.

I continued [my chat with Chat GPT](https://chat.openai.com/share/c8c76c08-712e-4dac-a1ba-5a521e5e55e1) about some of this if interested.

#### Monitoring and Tags

These ones are optional, and I think this is fine for now to pass these. There were already quite an amount of informations to digest so I'll see later on if I need it.

#### Done

Creation of the cluster takes some time but after one minute or two I am able to see it on the ECS page.

I see that I have a `Capacity Provider` associated to my cluster, this thing show me the details about my infrastructure. In my case, I disabled AWS Fargate and I only chose EC2 instances, so the only thing that I see is actually my `Auto Scaling Group` that I defined earlier. It would be interesting to see what's happening with Fargate or with Fargate *AND* EC2 instances, it will be for another time though.

I don't have any EC2 instances running as I specified the min of 0 and the max of 1. So I guess AWS took care of not launching a useless EC2 for me.

Let's use my cluster now.

### 8. Creating a task definition

Now that I have my cluster ready, I want to use it in order to deploy my application.

I am following [the second part of this youtube video guide](https://www.youtube.com/watch?v=zs3tyVgiBQQ) for this step.

In order to do that, the video tells me to create a `Task` in my cluster. Looking on the AWS documentation, I actually not ended up on the `Task` definition but on the [`Task Definition` definition](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html).

So a `Task Definition` is defined as a good old JSON containing the parameters of a `Task`, it includes many things like
- given my infrastructure, how do I want to launch my task,
- memory and CPU requirements,
- how much containers I want in my task,
- for each container,
  - which Docker image I want to use,
  - container port mapping,
  - env variables,
- etc...

So as I understand, I'll create this task definition once. It will describe how I plan to run my app. Once I have this, I'll be able to use this `Task Definition` in order to consistenly deploy my app.

On the documentation page, I also see that I will be able to run my `Task Definition` either as a `Task`, either as a `Service`. As I understand, a `Task` is a oneshot thing, e.g. `Run three tasks based on my task definition please`. A `Service` will run the task definition but also maintain the desired number of tasks in the ECS cluster in case a task fails or finishes, e.g. `I permanently want three tasks running based on my task definition please`.

Okay good, it clarifies a few things. I'll go create my `Task Definition` then.

So I am on the Task Definition page and I need to define a `task definition family name`, it's not simply a task definition name because AWS directly want to take into account possible revisions of my task definition. So every time I update my task definition, I'll add a new task definition with an incremented revision number to my nice task definition family.

#### Infrastructure

Then I need to specify my target infrastructure for my task, my favorite part.

As `launch type`, I need to choose between `AWS Fargate` or `EC2 instances`, since I disabled Fargate, I'll go only for `EC2 instances`.

Then, `Operating System/Architecture`, I need to choose between `Linux/X86_64`, `Linux/ARM_64` and a bunch of `Windows`. I will take the `Linux/X86_64` as I probably don't want to do stuff with `Windows` and I my cluster is composed of simple machines which are not `Linux/ARM64`.

Next, `Network mode`, the *Info* tells me "*The network mode specifies what type of networking the containers in the task use*". Ok. I dig a bit and find this [AWS documentation page](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-networking.html?icmpid=docs_ecs_hp-task-definition) describing a bit the different options for EC2 instances. I chose `default` as this is the default Docker networking option that I know a bit. I hesitated with `awsvpc` that will give my task the same networking properties than my EC2 instances, but with this one we necessarily have the host port equal to the container port, see [this page](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_PortMapping.html) so I'll stay with the `default`. The other options are related to the Docker options regarding network.

Then I need to specify my `task size`, as my beautiful `t2.micro` is 1vCPU and 1GiB of RAM, I set my task with 1vCPU and 1GB of memory.

Then I can give an IAM role to my task, it would make sense if I needed my task to hit on the AWS API, it's not my case so I don't choose any role (and don't have any setup anyway).

Then I have to defined the `Task execution role`. It is the IAM role for `the container agent`, OK. I dig up on this agent and found something on [AWS For Business Page](https://www.awsforbusiness.com/amazon-ecs-container-agent/#:~:text=The%20Amazon%20ECS%20container%20agent%20is%20a%20software%20that%20AWS,are%20unfamiliar%20with%20the%20concept.):
> Basically, the ECS container agent runs on each EC2 instance with an ECS cluster, and sends telemetry data about the tasks and resource utilization of that instance to the Amazon ECS service. It also has the ability to start and stop tasks based on requests from ECS.

So it's the software that will pull the image, start, stop and more generally manage the task, I understand why it needs an IAM role. AWS can create this role for me, so I'll let it do so.

#### Container

Now I need to define how many containers and the definition for each container. In my case, I need something simple: one container running my image.

So I create my only container with
- name: `AwsGuideUniqueContainer`,
- image URI: I find this one when going to ECR and checking the details of my (unique) image on my (unique) repository,
- ports:
  - container port: in my code, the default PORT is 3000 so that's what I'll use for the container port,
  - host port: I'll map this to the 8888 port (for no particular reason), this is the port I'll expect to use later on when interacting with my app,
- resource allocations:
  - CPU: 1 vCPU as this is what I have with my `t2.micro`,
  - GPU: 1 as it is the minimum allowed,
  - Memory hard limit: 1 GB as this is what I have with my `t2.micro`,
  - Memory soft limit: 1 GB.
- healthcheck: since I have a `health` route I can setup it. I modify the default version to `CMD-SHELL,curl -f http://localhost:3000/health || exit 1`. This command is ran inside the container so the targeted port is the container port, not the host port.


I leave the remaining optional configurations as default.


### 9. Running my Task

Okay so now I have my task definition, I just need to run it right?

I am following [the second part of this youtube video guide](https://www.youtube.com/watch?v=zs3tyVgiBQQ) for this step.

So I go back to my ECS cluster and I click on `Run new task`.

First, I specify that I want to run my task using my cluster.

Then for the `Deployment Configuration`, I want to run my `Task definition` as a `Task` and not a `Service`. In a real app, I would probably consider `Service` as I want my app to be always up, in my case I only want to test things so I choose `Task`.

I can select my task definition using its `family` and `revision number`. And I set the number of desired tasks as 1.

For the networking I use the networking of my cluster, so the VPC, subnets and Security Group that I previously "defined" when creating the cluster.

I let the other things as default.

Once I run the task, I see that an EC2 instances has been created.

Additionally, I see my task in the `provisioning` state. Issue is that it stays in the provisioning state undefinitely...

#### Mistake #1

I have an instance but I see that it has only 960 MB of available memory, so it's not enough for my task which needs something with at least 1GB. Therefore, I adust my task definition, for the task and my container, I set the CPU to 0.25 vCPU and for the memory I set 0.5 GB.

With that changed, I stop the existing task and run a new one with my latest task definition. Still infinite provisioning state...

#### Mistake #2

I made the mistake of asking for 1 GPU in my task definition, 0 was not an allowed input so I set 1. But my `t2.micro` does not actually have any GPU so this also explains why my task can not be provisioned by my existing EC2 instance.

So actually 0 is not an allowed input, but not setting the input is actually setting it at 0. I cried a bit but I now see that my new task is not provisioning undefinitely now, it starts and fails directly.

#### Mistake #3

When checking the logs of my task, I see an error of the kind `exec user process caused: exec format error`. I googled this and found the answer on [Stack Overflow](https://stackoverflow.com/questions/67361936/exec-user-process-caused-exec-format-error-in-aws-fargate-service). I have a M1 Macbook so the system architecture on which I built my docker image (ARM) is not the same than the one I try to run the image on. That's nice to learn and with that, I actually rebuilt my docker image with the proper target architecutre, re-pushed it to my repository on ECR and updated my task definition in order to use my new image.

```console
docker build --platform=linux/amd64 -t aws-guide-app .
```

#### Mistake #4

So my task is running now but I see it as `Unhealthy`. So it seems my healtcheck is failing.

I actually went a bit crazy on this one as I did not really know what to debug.

As a matter of fact, I learned that I could setup an healthcheck at the Docker image level. I followed this [documentation](https://lumigo.io/container-monitoring/docker-health-check-a-practical-guide/#:~:text=In%20addition%20to%20the%20CMD,health%20check%20every%2030%20seconds.).

This Docker healthcheck was very similar to the one I had put in my task definition. So I tried it to see if at least my healtcheck worked locally, and it did not. Here debugging was easier as I know quite well how to go in my Docker container but I still don't know how to SSH in my EC2 machine, another problem for another day. My issue is that `curl` was not installed.

So I modified my Dockerfile to add the installation, just after using the last base image `FROM alpine:3.18 AS final`
```docker
# Install curl
RUN apk add --no-cache curl
```

#### Done

Finally I am able to see my task running properly and my healtcheck passing!


### 10. Exposing my container to the internet

So now I have my task running on my EC2 instance. My goal is now able to hit the healtcheck route on this AWS machine.

I am following [the second part of this youtube video guide](https://www.youtube.com/watch?v=zs3tyVgiBQQ) for this step.

During the setup of the cluster, I specified the option `Auto-assign public IP` for the networks such that my EC2 instances automatically have a public address. So I try to visit this address with the port I have chosen in my task and the healthcheck route: `<EC2 instance address>:8888/health`. It does not work at all but it's actually expected.

My EC2 instances are all within the default security group, which does not allow for inbound internet access, apart from other resources within this security group. So I'll do a non safe thing here and directly modify the default security group in order to allow to hit on the port 8888 of my EC2 instances from anywhere.

For that I go the `security groups` section in AWS, I have only one security group, the default one. I click on it and edit the inbound rules. I add two new rules:
- allow trafic from any IPv4 to port 8888,
- allow trafic from any IPv6 to port 8888.

I did not really know the differences between IPv4 and IPv6 so I found this [nice article](https://www.geeksforgeeks.org/differences-between-ipv4-and-ipv6/).

### 11. Success

*With that updated, I can hit my healthcheck route, and it works, I see the JSON response.* 

This ends the first part of the serie where I learned the basic path to deploy a Docker image, store it on ECR and use it to run a task on ECS.


### 12. Preparing second iteration: adding a database in all that

I'm happy to be able to deploy my app using ECR and ECS! Now I would like to add a database and let my app connect to it.

So my first step is to modify my code in order to be able to connect to a database locally.

I chose [Postgres](https://www.postgresql.org/) as database, not because this is what I need, but because this is what I am the most used to in my projects.

Then I modified my codebase in order to be able to connect to database using the `DATABASE_URL` environment variable, the `healthcheck` route has been modified in order to also retrieve the health of the database by executing a dummy query against it. In this project, I don't care about real database usage which would include topics like migrations, tables or else, I just care about properly connecting to a database.

I also modified the `compose.yaml` in order to spawn a `Postgres` database in the docker compose, I actually modified just a few details around what `docker init` provided me at the start.

With that, I am all set and by running `docker compose up --build`, I can query my healthcheck route `curl http://localhost:3002/health` and get my updated response `{"db_ok":true,"ok":true}` (I don't really care about the format of the healtcheck response too by the way).

### 13. Create a database

So I looked a bit on how to create a Postgres on AWS, I found that I needed to go to [Amazon Relational Database Service (RDS)](https://aws.amazon.com/rds/).
As I liked my previous video, I looked for a video of the same guy than before about RDS, I found this [one](https://www.youtube.com/watch?v=vw5EO5Jz8-8). I watched it but it is not exactly what I want to do.

I'll go try to do the thing by myself!

So I go to RDS and go with the `Create database` link. 

My first choice is to choose a *Database creation method* between *Standard create* and *Easy create*, I'll go for *Standard create* as the video taught me that *Easy create* could lead to things that cost more money and that I would like to see the various options.

Then I need to choose an *Engine*, here I will go for the very simple *PostgreSQL*, I'll not got for Aurora. For a serious project, I think I would go for Aurora but in my case, I want to start with something dead simple.

I choose the latest *engine version* and then select the *Free tier*.

#### Enter the settings

I'll go quickly on the non interesting things.

- DB instance identifier: aws-guide-db-1,
- username & password: some stuff I chose,
- DB instance class: I don't have much choice here, free tier I guess. I'll go with the `db.t3.micro`, I don't really need performance anyway here,
- storage type: I stay with the default `General Purpose SSD (gp2)`,
- allocated storage: the minimum with 20GiB,
- I disable storage autoscaling,

#### Connectivity

A bit more involved piece here.

First I need to choose a *Compute resource* between *Don’t connect to an EC2 compute resource* and *Connect to an EC2 compute resource*. The second option is tempting but it asked me to select an EC2 instance by ID. So this is not really what I want since I don't know in advance which EC2 instance I have.

As I understand, this option is more if I have one static EC2 instance running in a different VPC and I want to automatically make the network changes. In my case, I plan to put everything in the default VPC so I expect to not have to do complex stuff for connection, to be confirmed. In any case, I can still go back to this later on so I will choose the first option *Don’t connect to an EC2 compute resource*.

Then I need to choose a *Network type* between `IPv4` and `IPv4 and/or IPv6`, I'll stay simple with only `IPv4` as it is written that `IPv6` would require additional configuration.

For VPC, subnet and VPC security group, I choose the default everytime as I want to stay within my default VPC where my task will be.

I disable the public access to the database as I want to interact with my DB only through my app.

I let the other options as default.

#### Database authentication

I choose only Password authentication. The addition of IAM database authentication seems promising but I don't want to deal with IAM for now as I cheat with my root user.

#### Other settings

I specify in the *Initial database name* that I want `awsguide`. Otherwise I would need to create this database later on.

I let everything else as default.

#### Database creation

I create my database. This took a few minutes!

### 14. Connecting the app to the database

First I push my new Docker image on ECR using the same process than previously.

Then I create a new `revision` for my task definition.
- I update the used image,
- I add a `DATABASE_URL` environment variable, the format is `postgresql://<Postgres user>:<Postgres password>@<Posgres host>:<Postgres port>/<Posgtres DB>`.


I have my new revision, I try to launch a task with it, I don't expect it to work but who knows.

Looks like it worked! I can query my healthcheck and it says everything is healthy!

I add a log in the `main.rs` to be sure connection is made. I create a new task definition and a new task. 

Ok everything seems to be working, great success!

I delete my database in order to not have to pay something. I will create it again if needed.

## Trying AWS Fargate instead of EC2 instances

Here is the list of steps that have been taken.

So I'm very happy with the first part, I learned a lot! Now I want to try to abstract a bit away the EC2 instances by trying out AWS Fargate.

Additionally, I often deal with admin applications that are used not that often and by a limited amount of users. For these kind of applications, it seems that the serveless approach of AWS Fargate makes more sense than EC2 instances.

By the way, I watched a [nice video](https://www.youtube.com/watch?v=buKoMUR9t84) (always the same guy) about the different *compute* possibilities on AWS. There are a lot to explore, but right now I want to try out Fargate.

I will follow [this video](https://www.youtube.com/watch?v=o7s-eigrMAI) for this part and see how it goes.

The list of steps will be updated below.

1. [Modifying my cluster](#1-modifying-my-cluster-actually-creating-a-new-one),
2. [Creating a new task definition](#2-creating-a-new-task-definition),
3. [Running as as task](#3-running-as-a-task),
4. [Creating a service](#4-creating-a-service),
5. [Creating a Service in default security group and Load Balancer in another security group](#5-creating-a-service-in-default-security-group-and-load-balancer-in-another-security-group),
6. [Integrating a CI/CD with a dummy app](#6-integrating-a-ci/cd-with-a-dummy-app),
7. [Integrating a CI/CD with our app](#7-integrating-a-ci/cd-with-our-app),


### 1. Modifying my cluster, actually creating a new one

So when I previously created my cluster on AWS ECS, I disabled the AWS Fargate compute option. I first need to re-activate it.

I have actually not found how to re-activate it by editting my cluster, I don't really know if this is possible or not. It makes sense to me that it is non necessarily editable as it is a big choice.

For now, I'll simply create a new cluster with only AWS Fargate! At least I will not have any conflicts between my EC2 instances and Fargate.

So I create my new cluster `AwsFargateGuideCluster` with only `AWS Fargate` enabled for my infrastructure.

Actually, all the remaining options are for `Monitoring` and `Tags`, which I don't really care about it for now so I'll let the defaults.

In terms of cluster setup, using AWS Fargate is extremely more simple than using EC2 instances!

My new cluster is now ready!

Taking a look at it and comparing it with my previous cluster, I am looking at the `infrastructure` tab.

In my previous cluster, I had one `Capacity provider` corresponding to the `Auto scaling group` I had defined (like 0 as min number of instances, 1 as max number of instances, etc...). In my new cluster, I have actually two `FARGATE` and `FARGATE_SPOT` but logically no `Auto scaling group`. I am not trying to understand for now what are the differences between `FARGATE` and `FARGATE_SPOT` but I read that there are automatically managed and I can not remove or edit them.

Let's continue

### 2. Creating a new task definition

The task definition I created in the fist part was actually setup for `EC2`, I explictly disabled `AWS Fargate`.

I first wanted to update my task definition, I could create a new revision with enabling both `EC2` and `AWS Fargate` **BUT** it forces the `network mode` of my task to `awsvpc` instead of `default`.

I don't want to break my first task definition so I'll just create a new one, dedicated to AWS this time around!

I'll go quickly for the creation as it is very close to the first task definition I created earlier:
- Operating system/arch: `Linux/X86_64`,
- Network mode: `awsvpc` is enforced,
- Task size: same than before, it's funny because here I can't write anything as previously with EC2, I need to choose among authorised possibilites,
  - CPU: .25 vCPU,
  - Memory: .5 GB
- Container settings, still only one container:
  - name: `AwsFargateGuideUniqueContainer`,
  - image URI: same than before,
  - port mapping: I choose the container port at `3000` as I will not add any `PORT` env variable and that my default value is `3000`,
  - resource allocation limits: same than before,
  - env variables: I add my `DATABASE_URL` value that I got from my running DB using AWS RDS,
  - healthcheck: same than before,
- other settings: all as default.

### 3. Running as a task

In the video, the task definition is directly used in a `Service`. In my case, I'll begin by simply running a single `Task`, I'll follow the instructions for the `Service` later on!

So I do as before and run my task by letting the task creation flow selecting `AWS Fargate` for my infrastructure.

I have my task running, I grab its public IP and query it with port 3000 and path `/health`, so like `<Task public IP>:3000/health`.

As expected it does not work because I need to allow inbound traffic on port 3000 in my default security group, I add the inbound rules for this.

And then it works!

All good on this side! Now let's go with the video with creating a service for this task definition!

### 4. Creating a service

I will simplify a bit my code and remove the database interaction for now. It is a pain to launch my DB and then delete it so I will stay simple with a code without database interaction. After my updates, I created a new task definition with family `AWSFargateGuideSimpleTaskFamily`.

Now let's go back to my cluster and create the service!

It looks quite similar than when launching a task for now. For the first part I need to define my compute options, I choose to use the `Capacity provider strategy` with `FARGATE`. As I understand this is meant to handle multiple capacity provider but it works with one in any case.

The second part is the deployment configuration, I specify here that I want to run a **Service** and I put my `AWSFargateGuideSimpleTaskFamily` task definition. I name my service `AWSFargateGuideSimpleTaskService` and I specify that I only want one task running.

The other options are actually filled by default, so it looks I could stop there. However the video talks about a `Load balancer` so I will try to setup one. I go to the `Load balancing` section.

I need to choose between `Application Load Balancer` and `Network Load Balancer`, I am interested in the `Application Load Balancer` as I want it to be my entrypoint at the HTTP level.

The `container` part is auto filled and the incoming traffic will be mapped to the port 3000 of my container, which is good.

Then I need to specify a name, I'll go with `AWSFargateGuideLB`.

Now we meet something new, I need to create a `Listener` that will define the listened connection requests to my load balancer. I'll stay with the default which is on `Port` 80 and using the HTTP protocol.

Another notion now with the `Target group`, it is used in order to route the requests to the tasks. As I understand it will keep an eye on which tasks are there, which are healthy or not in order to correctly route the requests. I'll keep the default settings but I will change the `Health check path` to `/health`.

I create my service and wait for a few minutes.

I see my service as `Active` and I see `1/1 tasks running`, looking good! I use the DNS name of the load balancer and try to query it with the path `<Load balancer DNS name>/health`, no response but this is expected, let's try to modify the default security group to allow incoming traffic for Port 80. I modified it, retriggered my query, and it works! Great!

Now, I cheated a bit as I have used my default security group for everything. In the video, the guy is using a custom security group, so I'm gonna do that next.

### 5. Creating a Service in default security group and Load Balancer in another security group

So from what I understood from the video, the goal is to create:
- one load balancer in one security group,
- one service that will run my task in my default security group.

Since the load balancer hits on the tasks of my service, I will need to make sure that the two security groups are properly configured in order to allow traffic. Actually, all I need is to allow incoming traffic coming from the load balancer security group to the default security group of my service and tasks.

Let's go then.

In the video, the guy creates beforehand a load balancer but let's see if I can do this within the service creation flow directly. It does not seem so, it would lead to a load balancer in the same security group. No worries, let's create one from scratch!

So I still want an `Application Load Balancer` and I will name it `AWSFargateGuideLB`.

It will be `internet-facing` and not `internal`, and I choose the `IPv4` as IP address type.

For the VPC, I will choose my default VPC and choose the three availability zones, it gives me the three associated subnets.

Now on the `Security groups`, I can only choose an existing so I open a new tab in order to create a new security group as I don't want the default one here.

#### Security group creation

I will choose the name as `AWSFargateGuideLB` and the default VPC.

By default I have no `inbound rules` and one `outbound rule` (allowing traffic to all IPv4 if I understand correctly).

I will want to access my load balancer from the internet, so I will add one inbound rule in order to allow all incoming traffic on Port 80 from IPv4.

Security group successfully created

#### Back to the load balancer

I choose my newly created `AWSFargateGuideLB` security group.

Now I need to setup the `Listeners and routing`, I need to create a `Target group` in order to know where I forward my requests. It opens a new tab.

#### Target group creation

For the target type, I will choose `IP addresses` because the video insisted on it. I understand that `instances` is when you work with EC2 instances directly and that `Lambda function` is for `Lambda functions`. However, there is also the `Application Load Balancer` type which seems promising, I will try this after. (I actually tried later on, but it was not possible to use it with Fargate as at it does not work with my network mode `awsvpc` of my task definition).

For the name, I choose `AWSGuideFargateLBTargetGroup`.

For the `Protocol port`, I will choose `3000` as this is on this port that my app will be exposed. And I also modify the healthcheck command to use `/health`.

#### Back to the load balancer

I can now choose my target group and I go for the creation!

#### Back to the service

Let's see if I can create my service with my new load balancer.

I can pick my `AWSFargateGuideLB` load balancer!

For the `listener`, I can choose the `use an existing listener` and select the listener on `80:HTTP`.

For the `Target group`, I can choose the `use an existing target group` and select the `AWSGuideFargateLBTargetGroup`.

I create my service but hitting on the load balancer gives me a 504, this is expected as I still need to allow traffic between my two security groups.

So I go to the security group part in AWS and I go for modifying my default security group. I will add an `inbound rule` in order to allow traffic coming to Port 3000 coming from my security group `AWSFargateGuideLB`.

I save this and try to hit on my load balancer DNS (with `/health`) and it works!

### 6. Integrating a CI/CD with a dummy app

I would now like to have some automation and try to automatically deploy my new code when I push it on the `main` branch. I found this [blog post](https://aws.amazon.com/blogs/opensource/github-actions-aws-fargate/) of AWS that introduce the main AWS Github Actions, let's dig a bit.


The blog post describes four Github Actions:
> We have open sourced the following actions at github.com/aws-actions:
> - github.com/aws-actions/configure-aws-credentials – Retrieves AWS credentials from GitHub secrets and makes them available for use by the rest of the actions in the workflow.
> - github.com/aws-actions/amazon-ecr-login – Lets you log into your ECR registry so you can pull images from and push them to your ECR repositories.
> - github.com/aws-actions/amazon-ecs-render-task-definition – Inserts the ID of a container image into the task definition for ECS.
> - github.com/aws-actions/amazon-ecs-deploy-task-definition – Deploys an updated task definition and image to your ECS service.


Looks exactly what I need, so let's try to integrate these.

I'll first follow what they do in the blog post, then I'll adapt it to my codebase.

#### Understanding a bit more IAM

So I previously created a user `AwsGuide`.

This user has a set of permissions, and as said by AWS directly
> Permissions are defined by policies attached to the user directly or through groups.

I don't want to handle `groups` for now so I'll go directly with the `policy`. There is a huge list of all the possible policies and it's not very easy for me to navigate in this. There are two ways to attach policies:
1. create an `inline policy` for the user: in this case, I directly browse the policies for one or more services (like ECR or EC2) and I add the ones I need,
2. attach a `managed policy` directly, as I understand, AWS has prepared some packages of policies that are commonly used together.

I will try to use the `managed policy` in my case. It is actually advised to give policy to `group` and not to `user` directly, so I'll go create my group `aws-fargate-ci` then.

I can directly attach some permissions policies. I find on [this page](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_job-functions.html#jf_developer-power-user) the `Developer power user job function` with the managed policy `PowerUserAccess`, it seems too broad for my case but I will start with that! I will then add my user to this group.

At the beginning of this work, I had added an inline policy to my user with full access to ECR, I will remove it as I expect my new managed policy to also provide this (and it does). Taking a look at this managed policy in AWS is actually not so easy because it contains some lower level managed policies, so I understand that it has a lot of things, but I don't grasp all of it. I know however that it can not create or manage accounts, which is good.

I will continue with the set up in the blog post and go back to this wheen needed.

The blog post contains some setup, I'll try to follow with the AWS CLI this time. Additionally, I'll need to do some actions in the CI so I will not be able to rely on our root user anymore.

#### Configuration of the ECR

I already have an ECR so I will not create a new one, but I still want to be able to read from it and ultimately push image in it.

I can query my repositories using `aws ecr describe-repositories --profile <my profile>` so it's all good on this side.

#### Task definition

I'll copy their task definition in `./aws/task-def.json`. The task is really simple at it directly echoes an HTML page. If I compare to my previous task definitions, there are a lot less things, but we'll try to underestand this better a bit later.

I'll register it using their command
```console
aws ecs register-task-definition --region eu-west-3 --cli-input-json file://./aws/task-def.json --profile <my profile>
```

I can see it on my AWS console so all good on this side!

#### Service creation

The blog post contains the creation of a cluster but I'll try to use the one I already have. Let's jump to the service.

I needed to adapt a bit the service creation command as I needed to point to my desired cluster and change the names of the subnets and security group. I still use my default VPC so I don't need to input this I guess.
```console
aws ecs create-service --region eu-west-3 --cluster AwsFargateGuideCluster --service-name sample-fargate-service --task-definition sample-fargate:2 --desired-count 2 --launch-type "FARGATE" --network-configuration "awsvpcConfiguration={subnets=[<my three subnets>],securityGroups=[<my default security group>]}" --profile aws-guide
```
PS: I did a bad manipulation so my revision number is 2 instead of 1.

So my service has been created but the tasks were failing. The error was something like `CannotPullContainerError: pull image manifest has been retried 5 time(s): failed to resolve ref docker.io/library/httpd:2.4: failed to do request: Head "https://registry-1.docker.io/v2/library/httpd/manifests/2.4": dial tcp <IP>: i/o timeout`

I have found this [post](https://stackoverflow.com/questions/76398247/cannotpullcontainererror-pull-image-manifest-has-been-retried-5-times-failed) with a similar error. So I am using a public subnet but I have neither a gateway, neither set `assignPublicIp` to `true`, so my task can't connect to the image registry in order to get its Docker image.

I will shut down my service and create a new one with this option enabled:
```console
aws ecs create-service --region eu-west-3 --cluster AwsFargateGuideCluster --service-name sample-fargate-service --task-definition sample-fargate:2 --desired-count 2 --launch-type "FARGATE" --network-configuration "awsvpcConfiguration={subnets=[<my three subnets>],securityGroups=[<my default security group>],assignPublicIp=ENABLED}" --assignPublicIp ENABLED --profile aws-guide
```

Okay now I have my service running, my tasks running, and I can visit the public IP of my tasks in order to get the setup HTML. Good stuff.

By the way, in order to make this work, I modified the inbound rules of my default security group in order to add inbound rules for PORT 80.

And since my service does not have any load balancer, I can not access my "service" directly, I need to go to the task directly. So it seems way more serious to have a load balancer in this case.

#### Setting up my repository

I'll add two secrets for my CI in the Github repository directly: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` that I obtain from my `AwsGuide` user on IAM. During the creation, AWS recommended another alternative for such a use case, I'll start with this but it would be interested to learn more about this alternative.

Then I'll add the workflows, for this I simply go to `actions` tab of my repository, GitHub recommends me a few and a select the `Deploy to Amazon ECS`. Instead of commiting this to `main`, I'll copy the content in `.github/workflows/aws.yaml` and commit it in a dedicated PR. I update the workflow to my needs:
- replacing the correct environment for my AWS resources,
- removing the `environment: production` as I don't have any environment in my repository,
- commenting the steps `build-image` and `task-def` as I don't build any Docker image for now, I then change in the last job the line `task-definition` to `task-definition: ${{ env.ECS_TASK_DEFINITION }}` in order to rely on my local file directly.

I create a [PR](https://github.com/VGLoic/aws-exploration/pull/1) with that, I also modify the `task-def.json` content to add a change to the HTML.

I merge the PR, got my [action](https://github.com/VGLoic/aws-exploration/actions/runs/8678702103/job/23796002866) running. The action was a success, good.

I see my new revision of my task definition with my updated HTML, I see that my tasks are now running with the new revision. But I don't have my updated HTML when I visit the task public IP. Almost perfect.

I will try to re-modify my HTML just to see what happens. Not working again.

I will try to delete the html file before creating it.

Okay actually it was working all along but I was only updating the `head` part of the HTML... But at least it works fine!

I will delete this service and I'll try to update this for our codebase now!


### 7. Integrating a CI/CD with our app

I'll try to start very simple, I want a minimal task definition and a minimal service, so no load balancer or logs or else.

For this I'll start from the task definition that I used in the step 5 above, get its JSON, and try to simplify it as much as possible when taking a look at my previous task definition for the blog post app.

I rename my `task-def.json` to `sample-app-task-def.json` and create the new `app-task-def.json`.

So I first try to register my new task definition but it fails with `An error occurred (ClientException) when calling the RegisterTaskDefinition operation: Fargate requires task definition to have execution role ARN to support ECR images`.

So originally, my imported task definition had a line `"executionRoleArn": "arn:aws:iam::<ID>:role/ecsTaskExecutionRole"`, I removed it. Now I take a better look at this task execution role on [AWS documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html). So my tasks need this role in order to pull the image from my ECR repository, looks fair.

I add back the line `executionRoleArn` and try again. Now it fails because it says that I don't have the `iam:PassRole` policy for the `role/ecsTaskExecutionRole`. Taking a look at what [it is](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html), it is a role that is allowing me as user to give the designated role to a service. In my case, my user is not allowed to give this famous `ecsTaskExecutionRole` to my task definition. I'll try to add it directly in my user group using an inline policy. The policy is in `IAM` service and I needed to specify that it acted on the `role` `ecsTaskExecutionRole`. Now let's try again.

Amazing it worked fine, I can now see my new task definition in my console.

Let's create a service with it now.
```console
aws ecs create-service --region eu-west-3 --cluster AwsFargateGuideCluster --service-name app-fargate-service --task-definition fargate-ci-guide:1 --desired-count 2 --launch-type "FARGATE" --network-configuration "awsvpcConfiguration={subnets=[<my three subnets>],securityGroups=[<my default security group>],assignPublicIp=ENABLED}" --profile aws-guide
```

Again, no load balancer or more complex settings. Let's see if it works.

I also modify my inbound rules of security group in order to allow incoming traffic to PORT 3000.

And it actually works, that's great news!

#### Let's setup the CI for this now!

I'll modify my workflow:
- the env variables need to be changed with new service name and app name,
- I enabled the steps in order to build and push my docker image, and update my local definition.


I'll update my healtcheck route to add an hardcoded `version` integer, just to be able to see the results.

I create a new [PR](https://github.com/VGLoic/aws-exploration/pull/2) for that. I merged it into main, the [action](https://github.com/VGLoic/aws-exploration/actions/runs/8678916140/job/23796627847) is a success and I can query my new healthcheck route and see my version number. Good stuff.

Now I would like to do the same but with a load balancer and adding the logs for my tasks.

#### Adding logs

My tasks did not have the logs enabled, I saw that in my previous task definitions, I had a part dedicated to logs. 

I'll try to add this to my new task definition and push this so see if it works directly.

So it failed, I am apparently missing the `logs:CreateLogGroup` policy. Let's take a look.

I added this policy to my `ecsTaskExecutionRole`, as I understand, it should be this role (that is given to the task) that should have this policy, so that's why I put it on the `ecsTaskExecutionRole`.

And now it works fine, I can see the logs. Okay that's good!

#### Adding a load balancer

I would also like to add a load balancer and disable the exposure of my tasks. I want a load balancer in the default security group for simplicity.

So let's take a look at the options in the [create-service command](https://docs.aws.amazon.com/cli/latest/reference/ecs/create-service.html).

There is a `--load-balancers` option, looks a bit complicated but let's try it.

```console
aws ecs create-service --region eu-west-3 --cluster AwsFargateGuideCluster --service-name app-fargate-service --task-definition fargate-ci-guide:<my revision number> --desired-count 2 --launch-type "FARGATE" --network-configuration "awsvpcConfiguration={subnets=[<my three subnets>],securityGroups=[<my default security group>],assignPublicIp=ENABLED}" --load-balancers targetGroupArn=<my target group ARN>,containerName=fargate-ci-guide-app,containerPort=3000 --profile aws-guide
```

Okay it does not work, as I understand, I need to create a load balancer beforehand, link it to my target group, and then it would work.

Let's do that, I'll go to my Target Group part of AWS console, and there is an action `Associate with a new load balancer`. I'll skip the creation details as it is similar to before.

So now that I have my load balancer, I can try again my command. This time the command worked!e

Now let's see if I have my tasks and if I can access it using my load balancer. Everything works fine! Now let's destroy the service and recreate it but without the `assignPublicIp`.

Okay so it failed with `ResourceInitializationError: unable to pull secrets or registry auth: execution resource retrieval failed: unable to retrieve ecr registry auth: service call has been retried 3 time(s): RequestError: send request failed caused by: Post "https://api.ecr.eu-west-3.amazonaws.com/": dial tcp 35.180.245.30:443: i/o timeout. Please check your task network configuration.`. Let's take a look!

So I found some pages that talk about this ([here](https://stackoverflow.com/questions/61265108/aws-ecs-fargate-resourceinitializationerror-unable-to-pull-secrets-or-registry) and [there](https://repost.aws/questions/QUvcwWlXxiT5qSq5-Gjxf0pg/how-to-to-launch-ecs-fargate-container-without-public-ip)), I also found [AWS documentation about task networking](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-networking.html). As I understand, by default a task does have a private IP and does not have a route to the internet and therefore not in my private ECR (which is actually outside of my VPC as I understand). The possible solutions I understand are:
- if I have a public subnet (which I have), I can enable `auto assign Public IP`. My task will then have a public IP that should be sufficient to talk within the VPC. If they would need to download from a public registry (like Docker Hub), it would be possible that I need to update my security group rules.
- I can setup an [AWS VPC endpoint](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html) in order to allow a connection (like the image pull) from my private ECR to the private IP address of the task in my VPC,
- I can setup a `Network Address Translation (NAT) gateway`(https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html) in my VPC. It would allow the private IPs of my tasks to connect to services outside my VPC (and also my ECR) without letting those services initiating a connection with my tasks.

I found a [good video](https://www.youtube.com/watch?v=jo3X_aay4Vs) of my guy related to this.

I'll first try with the AWS VPC endpoint as I am not really comfortable with the NAT Gateway. I'll use my root user for this, I go to `VPC Endpoint` and create one. I'll give it a name `ecr-api`. For the `category`, I will pick `AWS services`, it seems a bit generic but I am not sure that the others are really what I want. Now for the `Services`, I will pick only `com.amazonaws.eu-west-3.ecr.api` as I think I need only this one, I hope at least. I'll then pick my default VPC, default security group, my three subnets. And give a full access for my `Policy`.

It actually does not work. I read more carefully the [documentation](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html) and I actually need multiple endpoints:
- ecr-api: `com.amazonaws.eu-west-3.ecr.api` of type `interface`,
- ecr-dkr: `com.amazonaws.eu-west-3.ecr.dkr` of type `interface`,
- logs: `com.amazonaws.eu-west-3.logs` of type `interface` (since I want logs for my task),
- s3: `com.amazonaws.eu-west-3.s3` of type `gateway`(this one is needed as part of the images are on this).

With all that, my tasks are running, but without internet access, they just have direct connections to the needed AWS services through these VPC endpoints, pretty nice!


## Infrastructure as code using Terraform

So I already learned a lot of interesting things but now I would like to be able to automate even more things. Currently, the CI only works if I have my cluster and my service ready, which also implies a load balancer and possibly a database. I would like to automate everything in such a way that I don't need to prepare all this before leveraging my CI.

As I understand, this is why tools like [Terraform](https://developer.hashicorp.com/terraform) exist. I should be able to define what I want in AWS using code, and then use Terraform to setup all that consistenly, repeatably, automatically and efficiently.

For this new work, I will first start with the [Get started with AWS on Terraform series](https://developer.hashicorp.com/terraform/tutorials/aws-get-started). So with this, I learned how to setup Terraform, setup the AWS provider and use it in order to create an EC2 instance, and I put all that in Terraform Cloud. 

Here are the list of steps
1. [Creating my cluster](#1-creating-my-cluster),
2. [Exploring task definition](#2-exploring-task-definition),
3. [Adding a load balancer](#3-adding-a-load-balancer),
4. [Removing public IP from tasks](#4-removing-public-ip-from-tasks),
5. [Running in CI](#5-running-in-ci),
6. [Stop using default resources](#6-stop-using-default-resources)


### 1. Creating my cluster

So now I would like to use Terraform in order to create my cluster. I would like a cluster with Fargate, quite similar to the one I already have.

I will put my terraform code in the `terraform` folder. I will follow the [documentation here](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) and compare with my existing cluster.

Okay I end up with this for my `main.tf`
```tf
terraform {
  cloud {
    organization = "slourp-org"
    workspaces {
      name = "ecs-fargate-guide"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "eu-west-3"
}

resource "aws_ecs_cluster" "app_cluster" {
  name = var.cluster_name
}

resource "aws_ecs_cluster_capacity_providers" "fargate" {
  cluster_name = aws_ecs_cluster.app_cluster.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}
```

I still want to use `Terraform Cloud` so I'll let the cloud provider with my organisation. The cluster is very simple as I let most of the options as default, I only specify my capacity provider with the Fargate ones.

I apply the changes `terraform apply`, and I have my cluster, looks very good.

### 2. Exploring task definition

Let's see if I can declare my task definition now.

I will go to the [associated documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition). I see that there are some way to use a declared file, but it does not seem I can directly using it.

I also see that there is a difference between `resource` and `data source` in Terraform. From the documentation about [data source](https://developer.hashicorp.com/terraform/language/data-sources)
> Data sources allow Terraform to use information defined outside of Terraform, defined by another separate Terraform configuration, or modified by functions.

I'll start with a data source I think, I'll move this to a dedicated resource but later on. Right now I would like to simply access my existing task defintion.

The documentation also contains some quick explanation on how to launch a service associated with it, I'll go for that.

Actually I needed to add a few things to make everything work. In particular, some data sources about my default `VPC` and the associated default subnets.

I therefore added
```tf
data "aws_ecs_task_definition" "service" {
  task_definition = "fargate-ci-guide"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {}

resource "aws_ecs_service" "service" {
  name          = "app-service"
  cluster       = aws_ecs_cluster.app_cluster.id
  desired_count = 2

  task_definition = data.aws_ecs_task_definition.service.arn

  launch_type = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    assign_public_ip = true
  }
}
```

Once I applied all this, I have my cluster, my service and 2 tasks running with the latest version of my task definition, pretty neat!

### 3. Adding a load balancer

I would like to add a load balancer for my service, I'll take a look at the [service config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) and the [load balancer one](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb).

Let's start with my load balancer, I will put it in my default security group and with my default subnets.

```tf
resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [data.aws_security_group.default.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "app_target_group" {
  name        = "app-target-group"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path = "/health"
  }
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_target_group.arn
  }
}
```
We re-create what we previously created using the AWS console, but this time with code. It looks pretty good for now!

Now we can update our service with our load balancer that will be created
```tf
resource "aws_ecs_service" "service" {
  name          = "app-service"
  cluster       = aws_ecs_cluster.app_cluster.id
  desired_count = 2

  task_definition = data.aws_ecs_task_definition.service.arn

  launch_type = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [data.aws_security_group.default.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_target_group.arn
    container_name   = "fargate-ci-guide-app"
    container_port   = 3000
  }
}
```

Not gonna lie, I had a few bumps but quite OK to solve. Now everything works so quite happy!

### 4. Removing public IP from tasks

So now I would like to remove the `assign_public_ip = true`, I already know I will need the `AWS VPC endpoints` defined previously. I take a look at the [documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) and here we go.

So I modified the `assign_public_ip` to false and I added the following
```tf
##################################################################
################### DECLARING MY VPC ENDPOINTS ###################
##################################################################

data "aws_route_table" "default" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.eu-west-3.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [data.aws_route_table.default.id]
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.eu-west-3.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [data.aws_security_group.default.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.eu-west-3.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [data.aws_security_group.default.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.eu-west-3.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [data.aws_security_group.default.id]
  private_dns_enabled = true
}
```

Everything was quite straightforward based on what I made before. The thing that took me a few hours of debugging was the `privacy_dns_enabled = true` param which was needed, as they say in the doc
> Most users will want this enabled to allow services within the VPC to automatically use the endpoint

Making good progress, that's nice!

### 5. Running in CI

I would like to update my CI now. I would like to have a GitHub action that allows me to trigger a `terraform apply` or something like that. I don't necessarily want to update everything on push to `main` as I don't want my environment always up.

Let's see what I can do.

I started with this [page on Terraform talking about automation](https://developer.hashicorp.com/terraform/tutorials/automation/automate-terraform). Having a proper way of reviewing the changes, i.e. putting human verification between `terraform plan` and `terraform apply`, is actually non trivial. In this case, it seems that relying on something like Terraform Cloud actually helps a lot as it allows me to properly orchestrate the proposals.

I continue with the [specific page for GitHub actions](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions). It's interesting. It actually looks like my situation will not be that straightforward to handle. The issue is that I need to push my new action to AWS ECR, create my new task definition revision and then I would like my plan to use it.

One way would be to use Terraform "only" for setting up the infrastructure. Then I would use my current workflow to push to ECR, create my task definition revision and update my ECS service with it.

I will start very simple, not necessarily what I want but simple. I'll update my existing workflow in order to plan and apply my infrastructures on `push` on `main`, so it should go something as
1. push image to ECR,
2. create new task definition revision,
3. plan the changes the new task definition revision,
4. apply the plan.

Basically, I remove the `Deploy Amazon ECS task definition` step from before and replace it with Terraform.

So I followed the documentation and it worked well, I have the updates contained in this [PR](https://github.com/VGLoic/aws-exploration/pull/3).

In terms of workflow though, I'm not sure this is what I want, in particular for this kind of repository.

On a more serious project (but still simple), I would probably dissociate the setup of the whole cluster from the update of the service. If I would keep the terraform setup within the repository I could have
- one workflow dispatch for creating a fresh plan and applying it,
- one workflow dispatch for destroying the infrastructure,
- on PR: preview plan,
- on push on main: push image to ECR, create new task revision, update service (if up).

But if I separate the terraform code from the app code, I would strongly consider the "recommended" [Version Control System driven workflow](https://developer.hashicorp.com/terraform/tutorials/cloud-get-started/cloud-vcs-change) of HCP Terraform (new name of Terraform Cloud). With that I would have on the new repository:
- on PR: preview plan,
- on push on main: apply plan.
And on the code repository, I would have:
- on push on main: push image to ECR, create new task revision, update service (if up).

In another commit, I will revert my changes as I don't want to create my whole infrastructure on push on `main`.

### 6. Stop using default resources

I now would like to not rely on default resources of AWS. So I would like to create everything from scratch, VPC, subnets, security groups etc...

I have found a [nice first article](https://spacelift.io/blog/terraform-aws-vpc) talking about creating a VPC from scratch with Terraform, I'm gonna start with that.

Disclaimer: I found that Terraform exposes some [already made `modules` for AWS VPC](https://github.com/terraform-aws-modules/terraform-aws-vpc), I think that for serious projects, I would go with that instead of creating a new one from scratch.

The first step was to create the VPC, the public and private subnets, the route tables and the internet gateway. The Terraform code looks like as follows
```tf
###########################################
################### VPC ###################
###########################################

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "AWS Fargate Guide VPC"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)

  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)

  tags = {
    Name = "Private Subnet ${count.index + 1}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "AWS Fargate Guide VPC IG"
  }
}

resource "aws_route_table" "rt_for_internet" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Route Table for internet access"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.rt_for_internet.id
}
```

It was interesting to apply step by step the changes and follow on the AWS console in order to understand what resource we create and with which links.

I also check the Security Group and I saw that I had a default one associated to my default VPC.

I will try to deploy my stack with that. I will start by using only the public subnets. And I also add an inbound rule to my default security group in order to allow traffic to port 80. 

In terms of code, I copy pasted what I had before but making some adjustements:
- I had to add `enable_dns_support = true` and `enable_dns_hostnames = true` for my VPC, it was needed for the VPC endpoints,
- I updated my `aws_security_group` data by specifying the VPC I wanted, i.e. `vpc_id = aws_vpc.main.id`,
- I used my VPC everywhere I could with `vpc_id = aws_vpc.main.id`,
- I updated the `subnets` attributes with `[for subnet in aws_subnet.public_subnets : subnet.id]`,
- I used my second route table for the `s3 VPC Endpoint`, i.e. `route_table_ids   = [aws_route_table.rt_for_internet.id]`.

Everything is working well with that.

Now I try to use my private subnets for my ECS service but I keep my public subnets for my Load Balancer, let's see what is happening. I am still using my default security group.

I had an issue with the endpoints because I was considering the route table I created for my public subnets while I needed to take the other route tables, the one for the private subnets.

Other than that, it is working well!

### 7. Stop using the default security group

So I have one last thing where I am using the default and it is the Security Group. I would like to create a dedicated one and be able to set the inbound and outbound rules I need. The [documentation page](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) contains a lot of things but I managed to have the thing I wanted. I did a mimic of the default security group but now I have full control over it. Here is the code below
```tf
######################################################
################### SECURITY GROUP ###################
######################################################

resource "aws_security_group" "allow_traffic" {
  name        = "AwsFargateGuide Allow Traffic VPC"
  description = "Allow all outbound traffic, allow inbound traffic within a VPC, allow inbound traffic on port 80"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "AwsFargate Allow Traffic VPC"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_ipv4_port_80" {
  security_group_id = aws_security_group.allow_traffic.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_ipv6_port_80" {
  security_group_id = aws_security_group.allow_traffic.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_all_traffic_within_security_group" {
  security_group_id            = aws_security_group.allow_traffic.id
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.allow_traffic.id
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_traffic.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}
```

The pieces where I had a hard time was constructing exactly the rules I needed. What I wanted was
1. allow inbound IP v4 traffic on port 80,
2. allow inbound IP v6 traffic on port 80,
3. allow all inbound traffic within the security group,
4. allow all outbound ipV4 traffic.

I removed the data source for the default security group, i.e. `data "aws_security_group" "default"` and used everywhere my new resource.

Everything works well and I don't have any default in my configuration now, so more control and less bad surprises.

## Development

This repository uses the [rust language](https://www.rust-lang.org/), make sure to have it installed before going further. Installation instructions can be found [here](https://www.rust-lang.org/tools/install).

In order to install dependencies and verify that everything is fine, start by building the project
```console
cargo build
```

Start the server
```console
cargo run
```

