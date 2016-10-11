Install and upgrade Deis Workflow PaaS in AWS without fuss
========================

It allows to install [Deis Workflow PaaS](https://deis.com/workflow/) on to AWS with persistent [Object Storage](https://deis.com/docs/workflow/installing-workflow/configuring-object-storage/) set to AWS S3 and Registry to ECR and has an option to set PostgreSQL database to off-cluster use.

How to install
----------

Clone repository:

```
$ git clone https://github.com/rimusz/deis-workflow-aws
```

Rename/copy `settings.tpl` file to `settings`, then set S3 region, and AWS keys `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` there:

```
# overall Workflow settings

# buckets S3 region
BUCKETS_S3_REGION=us-west-1

# AWS credentials
AWS_ACCESS_KEY_ID=your_aws_access_key_id
AWS_SECRET_ACCESS_KEY=your_aws_secret_access_key
```

Also if you rename/copy `postgres_settings.tpl` file to `postgres_settings`, then you can set there [PostgreSQL](https://deis.com/docs/workflow/installing-workflow/configuring-postgres/) database to off-cluster.
You can set the Postgres database in Kubernetes cluster or use RDS one.

How it works
------------

```
$ ./install_workflow_2_aws.sh
Usage: install_workflow_2_aws.sh install | upgrade | deis | helmc | cluster
```

You will be able:

- install - sets Object Storage in specified AWS region in `settings` file
- upgrade - upgrades to the latest Workflow version (use the same region as was for install)
- deis - fetches the latest Workflow `deis` cli
- helmc - fetches the latest [Helm Classic](https://github.com/helm/helm-classic) cli
- cluster - shows Kubernetes cluster name

What the [install](https://deis.com/docs/workflow/installing-workflow/) will do:

- Gets Kubernetes cluster name which is used to create S3 buckets and Helm chart
- Downloads lastest `helmc` cli version
- Downloads lastest `deis` cli version
- Adds Deis Chart repository
- Fetches latest Workflow chart
- Sets storage to S3
- Sets Registry to ECR
- If `postgres_settings` file found sets PostgeSQL database to off-cluster
- Generates chart
- Installs Workflow
- Shows `deis-router` external IP

What the [upgrade](https://deis.com/docs/workflow/managing-workflow/upgrading-workflow/) will do:

- Downloads lastest `helmc` cli version
- Downloads lastest `deis` cli version
- Fetches latest Workflow chart
- Fetches current database credentials
- Fetches builder component ssh keys
- Sets Storage to S3
- Sets Registry to ECR
- If `postgres_settings` file found sets PostgeSQL database to off-cluster
- Generates chart for the new release
- Uninstalls old version of Workflow
- Installs new version of Workflow

### have fun with Deis Workflow PaaS of deploying your 12 Factor Apps !!!

## Contributing

`deis-workflow-aws` is an [open source](http://opensource.org/osd) project, released under
the [Apache License, Version 2.0](http://opensource.org/licenses/Apache-2.0),
hence contributions and suggestions are gladly welcomed!
