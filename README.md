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
docker build -t aws-guide-app .
```

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

