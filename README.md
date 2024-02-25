# Deploy a Web server to AWS

The goal of this repository is to implement a trivial web server, deploy it on AWS and describe the process along the way.

## Service description

This is a simple webserver exposing one healthcheck route `GET /health`. The associated handler will check the health of a connected `postgres` database and answer a status `200` response with a JSON body `{ ok: true, services: { database: true } }`.

## Steps

Here is the list of steps that have been taken when developing and deploying the services.

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

During the creation process of the Dockerfile, I set that the listening port was `3000` and as a consequence, the `EXPOSE 3000` command has been added in the Dockerfile. **However**, I don't really know in advance which `port` I will use since I setup the exposed `port` in my service as controlled by the `PORT` env variable. The `EXPOSE` cmd is actually not publishing and acts as a documentation between the Dockerfile and the developer running it, as [the documentation](https://docs.docker.com/engine/reference/builder/#expose) explains. Therefore, I remove the `EXPOSE 3000` line in my Dockerfile and I will handle the exposed `PORT` when running my container.

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

Way later on, the goal will be to perform deployment using code and to integrate the deployment it in the CI.

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

### 7. Creating a ECS cluster

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

The last option I need to the `networks` part is the `Auto-assign public IP`. If I turn this on, my EC2 instances will have a public IP address automatically assigned. While I don't think this is what I would like for a serious setup, I will turn on this one as I will need to access what is running on my EC2 instance later on.

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
  - env variables.

So as I understand, I'll create this task definition once. It will describe how I plan to run my app. Once I have this, I'll be able to use this `Task Definition` in order to consistenly deploy my app.

On the documentation page, I also see that I will be able to run my `Task Definition` either as a `Task`, either as a `Service`. As I understand, a `Task` is a oneshot thing, e.g. `Run three tasks based on my task definition please`. A `Service` will run the task definition but also maintain the desired number of tasks in the ECS cluster in case a task fails or finishes, e.g. `I permanently want three tasks based on my task definition please`.

Okay good, it clarifies a few things. I'll go create my `Task Definition` then.

So I am on the Task Definition page and I need to define a `task definition family name`, it's not simply a task definition name because AWS directly want to take into account possible revisions of my task definition. So every time I update my task definition, I'll add a new task definition with an incremented revision number to my nice task definition family.

#### Infrastructure

Then I need to specify my target infrastructure for my task, my favorite part.

As `launch type`, I need to choose between `AWS Fargate` or `EC2 instances`, since I disabled Fargate, I'll go only for `EC2 instances`.

Then, `Operating System/Architecture`, I need to choose between `Linux/X86_64`, `Linux/ARM_64` and a bunch of `Windows`. I will take the `Linux/X86_64` as I probably don't want to do stuff with `Windows` and I my cluster is composed of simple machines which are not `Linux/ARM64`.

Next, `Network mode`, the *Info* tells me "*The network mode specifies what type of networking the containers in the task use*". Ok. I dig a bit and find this [AWS documentation page](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-networking.html?icmpid=docs_ecs_hp-task-definition) describing a bit the different options for EC2 instances. The first one is the `awsvpc` that will give my task the same networking properties than my EC2 instances, it looks good enough for me for now. The other options are related to the Docker options regarding network.

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

#### Done

Finally I am able to see my task running properly!


### 10. Exposing my container to the internet

So now I have my task running on my EC2 instance. My goal is now able to hit the healtcheck route on this AWS machine.

I am following [the second part of this youtube video guide](https://www.youtube.com/watch?v=zs3tyVgiBQQ) for this step.

During the setup of the cluster, I specified the option `Auto-assign public IP` for the networks such that my EC2 instances automatically have a public address. So I try to visit this address with the port I have chosen in my task and the healthcheck route: `<EC2 instance address>:8888/health`. It does not work at all but it's actually expected.

My EC2 instances are all within the default security group, which does not allow for inbound internet access, apart from other resources within this security group. So I'll do a non safe thing here and directly modify the default security group in order to allow to hit on the port 8888 of my EC2 instances from anywhere.

For that I go the `security groups` section in AWS, I have only one security group, the default one. I click on it and edit the inbound rules. I add two new rules:
- allow trafic from any IPv4 to port 8888,
- allow trafic from any IPv6 to port 8888.

### 11. Success

*With that updated, I can hit my healthcheck route, and it works, I see the JSON response.* 

This ends the first part of the serie where I learned the basic path to deploy a Docker image, store it on ECR and use it to run a task on ECS.


TODO:
- Need to try to remove healthcheck to see.
- Need to play with ports
- What is IPv4 and IPv6?

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

