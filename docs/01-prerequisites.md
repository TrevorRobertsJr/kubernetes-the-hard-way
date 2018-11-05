# Prerequisites

## Amazon Web Services

This tutorial leverages the [Amazon Web Services](https://aws.amazon.com) to streamline provisioning of the compute infrastructure required to bootstrap a Kubernetes cluster from the ground up. [//]: # ([Sign up](https://cloud.google.com/free/) for $300 in free credits.

[Estimated cost](https://cloud.google.com/products/calculator/#id=78df6ced-9c50-48f8-a670-bc5003f2ddaa) to run this tutorial: $0.22 per hour ($5.39 per day).)



> The compute resources required for this tutorial exceed the AWS free tier.

## Amazon Web Services CLI

### Install the Amazon Web Services CLI

Follow the Amazon Web Services CLI [documentation](https://docs.aws.amazon.com/cli/latest/userguide/installing.html) to install and configure the `aws` command line utility.


### Set a Default Compute Region and Zone

This tutorial assumes a default region has been configured. In this tutorial, we will be using us-east-1

If you are using the `aws` command-line tool for the first time `configure` is the easiest way to do this:

```
aws configure
```

Consult the AWS [documentation] (https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) for further details on the CLI configuration.

## Running Commands in Parallel with tmux

[tmux](https://github.com/tmux/tmux/wiki) can be used to run commands on multiple compute instances at the same time. Labs in this tutorial may require running the same commands across multiple compute instances, in those cases consider using tmux and splitting a window into multiple panes with `synchronize-panes` enabled to speed up the provisioning process.

> The use of tmux is optional and not required to complete this tutorial.

![tmux screenshot](images/tmux-screenshot.png)

> Enable `synchronize-panes`: `ctrl+b` then `shift :`. Then type `set synchronize-panes on` at the prompt. To disable synchronization: `set synchronize-panes off`.

Next: [Installing the Client Tools](02-client-tools.md)
