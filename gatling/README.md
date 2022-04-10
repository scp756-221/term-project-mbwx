# Guide—Gatling
## Introduction
This Guide builds and runs the gatling test for our services under linux.
## Setup
### 1. Installation
Download the gatling bundle from [here](https://gatling.io/open-source/), and unzip the file, we should get the gatling folder. For future convenience, we rename the folder to gatling and move it to `/opt`. 
Open up the gatling folder, we should have the following structure:
![](/gatling/src/image1.png) \
We will only focus on the user-files folder.
Inside the user-files folder, we have two subfolders: resources and simulations. We put our simulation code in Simulations and helper data in resources.
### 2. Start the cluster
In this guide, we run the cluster on AWS through eks.
### 3. Gatling simulation script
In the Gatling folder, we have a scala code called **ReadTables.scala**. It has following simulations: \
**ReadUserSim/ReadMusicSim**: Test get method of User/Music \
**ReadBothVaryingSim**: Test get method of User and Music with random pause time.
### 4. Gatling script
To start gatling test, we need a script to connect with cluster and gatling. We build a script with following code:
![](/gatling/src/image3.png) \
**Cluster_ip** is the ip address of your AWS cluster, it can be got from AWS console or by getip.sh. \
**USERS** is the number of users in the simulation. \
**SIM_NAME** is the name of the simulation that will be run. Here it should be one of ReadUserSim, ReadMusicSim or ReadBothVaryingSim. \
**–label** is used by kill-gatling.sh to stop the simulation

## Running Gatling
With everything set up, we can now run the Gatling script. It will return the code of docker image. Checking the logs by the command `docker logs ${image code}` to get the testing result. It should have similar result with following screenshot:
![](/gatling/src/image2.png) \
The number of **OK** is the number of success requests, and the number of **KO** is the number of failed requests. \
Following the ReadMusic line, there are three more statistics values: \
**Waiting** represents the number of users that have not yet begun making requests. \
**Active** represents the number of users that are currently making requests. \
**Done** represents the number of users that are currently finished making requests. \
