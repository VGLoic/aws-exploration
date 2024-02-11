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

