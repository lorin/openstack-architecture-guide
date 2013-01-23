# Architecting your first cloud with OpenStack

## Introduction

If you're new to OpenStack, you'll soon discover that it isn't a software package that can simply be run as-is to provide an infrastructure-as-a-service  (IaaS) cloud. Instead, it's more of a toolkit that lets you integrate a number of different technologies in order to construct a cloud. This approach provides an administrator with a lot of flexibility.  But the large degree of flexibility can be bewildering for first-time administrators. (KVM, Xen, LXC or VMWare? Ceph or Swift? LVM or ZFS? Quantum or nova-network? RabbitMQ, Qpid, or ZeroMQ?)

The goal of this manual is to provide system administrators with guidance in deploying their first non-trivial OpenStack cloud. If this guide succeeds in its aim, after reading it you should have a better sense of how your compute, networking, and storage resources will be organized, as well as which of the various OpenStack-supported compute, storage, and networking back-ends you should select for your particular needs.

This guide is more opinionated than other OpenStack documentation, because the aim is to help the reader make decisions among different options provided by OpenStack.

This guide does not go into detail about how to install OpenStack on your hardware once you have decided how you will deploy it. For step-by-step details on how to perform the installation, see the [OpenStack installation documentation][install].

## Terminology

In this document, we use the term *nodes* to refer to the physical machines that will run the various services. We use the term *instances* to refer to virtual machines. We avoid the use of the term *servers* to avoid confusion, since it often connotes physical machines but the OpenStack Compute API uses this to refer to virtual machine instances.

## General issues to consider

Keep in mind the following isssues as you make design decisions.

### Performance

From the end-user point of view, a cloud provides the user with the illusion of infinite computing and storage resources. As an administrator, your actual resources are always finite. You need to have a sense of the CPU, memory, storage and networking usage of the different services in order to understand how much hardware you need and how to best distribute the different services.

In some cases, the performance needs of nodes will be obvious. For example, if you want a compute node to be able to support 8 CPUs worth of virtual machines, with a total of 16 GB of RAM across all of the VMs, and a total of 500 GB of storage across the VMs, and you don't want to overcommit resources (i.e., you will reserve one physical core on the compute node for each virtual core, and one GB of physical RAM on the compute node for each GB of virtual RAM), then you know that your compute nodes will need at least 8 CPUs, 16GB of RAM, and 500 GB of storage, plus a little extra to accommodate the host operating system.

If you want to support allowing users to create new virtual machine images from running instances, you need to make sure there's enough free space on your compute node to support this. To create a new image from a running instance, a temporary file will be created in (by default) /tmp of the compute node, and the size of this file is the size of the primary disk partition of the running instance. You need to make sure that the compute node has sufficient free storage to support this for the largest instance types you are going to support.

If you know you want to support 100TB of object storage, you'll need more than 100TB worth of physical storage to provide your users with access to 100TB worth of storage, because you'll need to use replication to protect against failures of individual disks or nodes. How much extra you need depends upon your replication strategy. You'll also need to understand the CPU and RAM needs of the services associated with your object storage backend.

Finally, you'll need to have a sense of the networking traffic you'll expect to see in your cloud.  Networking traffic will be caused by:

 * API requests from end-users
 * An image file copied to a compute node before the virtual machine can boot(*)
 * Communication among nova-* OpenStack services over the RabbitMQ message queue
 * OpenStack services querying the database
 * Accessing block storage
 * Network file share activity (if supported shared storage live migration)
 * VM migration
 * Any network activity in/out of the user-controlled VMs
 * Object storage data accesses (reads, writes)
 * Object storage rebalancing if a storage node is added/removed

(*) This only happens the first time the instance is booted, after which it remains in the cache.

### Maintenance and fault tolerance

Eventually, a physical node in your cloud will go down. When a node is intentionally brought down in a controlled fashion, we call this "maintenance". When it comes down in an uncontrolled fashion, we call it something else. (Generally, we use the term "fault" to indicate if there's a problem with a component in the system, and a "failure" to indicate whether the overall system does not behave property from the point of view of the users. Hence the use of the term *fault-tolerant* to describe systems where faults are present but do not lead ot failures).

Your architectural decisions will affect how difficult it is to do maintenance on your cloud, as well as how well your system can tolerate faults.

### Security

Security is a concern when implementing your network architecture. An OpenStack cloud runs a number of different services that communicate over the network, and you want to ensure that external users can only reach services that they need to, and not any of the other ones.

For example, external users will need to be able to make direct connections to your API endpoints to use your cloud. On the other hand, they should never need to make direct connections to your compute nodes or storage nodes. Your network architecture will be particularly dependent on these types of security issues.

### Scalability

At some point, once you have deployed a cloud into production, if it's successful then utilization will increase and you'll need to add new compute and storage nodes to keep with the increased demand. How easy is to add nodes to an existing cloud

## Choosing a Linux distribution

You need to choose what Linux distribution you will install on your nodes. Your choice should balance your familiarity with the distribution against how well supported it is by OpenStack. The [OpenStack installation documentation][install] currently covers Ubuntu, RHEL, CentOS and Fedora, pick whichever of these distributions you are most comfortable with.

If you have no prior preference about Linux distribution, we recommend Ubuntu, as it has actively maintained packages for OpenStack, and there's a large userbase of Ubuntu OpenStack users, which can be helpful when you run into trouble and ask the community for support.

## Choosing a hypervisor
You must decide which hypervisor that you want to run on your cloud. OpenStack supports multiple hypervisors, including KVM, Xen, QEMU, LXC, ESXi (VMWare), and Hyper-V. KVM and Xen are the most actively supported hypervisors in OpenStack, so we recommend you choose one of those two, unless you need a particular feature that is better supported by  another hypervisor (e.g., Hyper-V for running Windows instances, LXC for direct address to hardware devices running in the host).

In deciding between KVM and Xen, we recommend you choose the hypervisor that you are most familiar with. Some features of OpenStack are only supported on KVM, and others are only supported by Xen. See the [hypervisor support matrix][hsm] on the OpenStack wiki for more details about these features. Howeve, the differences in supported features across KVM and Xen are minor and unlikely to be a determining factor in choosing which hypervisor to deploy.

If you have no prior preference about hypervisor, we recommend using KVM. Setting up with KVM is documented in more detail in the [OpenStack installation documentation][install]. In addition, many of the [Quantum plugins][quantum-plugins] are only supported with KVM. We also have an impression that KVM is the more commonly deployed hypervisor among OpenStack users, although we are not aware of any formal survey of users to support this hypothesis.

## Deciding what features to support
OpenStack supports a number of optional features, and you must decide which featuers you want your cloud to support, as the use of certain features will affect architecural decisions. The features that can have significant impact on your architecture are:

* Storage issues (object storage and block storage)
* Network issues (level tenant isolation, public IP address for instances)
* Live migration (moving an instance from one host to another)
* High availability (tolerating faults in individual components)

## Storage issues

If you only deploy OpenStack Compute (nova), your users will not have access to any form of persistent storage by default: the disks associated with virtual machines are "ephemeral" by default, meaning that (from the user's point of view) they effectively disappear when a virtual machine is terminated. You need to identify what type of persistent storage you want to support for your users. Today, OpenStack clouds can explicitly support two different types of storage, object storage and block storage.

Object storage is a form of storage where you access binary blobs through an HTTP interface. S3 is a well-known example of an object storage system. OpenStack is designed to allow you to store your virtual machine images inside of an object storage system. You also may choose to allow your users to access the object storage system.

Block storage is a form of storage that is exposed as a block device. Users interact with block storage by attaching volumes to their running virtual machine instances. These volumes are persistent, in the sense that they persist even after the associated virtual machine has terminated. Block storage is implemented in OpenStack by the Cinder project. Cinder supports multiple back-ends, and you must choose what back-end you want to use if your cloud will support block storage.

File storage, or filesystem storage is a form of storage that is exposed as files in the local file system. Most users, if they have used a network storage solution before, have encounterd this form of networked storage. In the Unix world, the most common form of this is NFS. In the Windows world, the most common form is called CIFS (previously, SMB). An OpenStack cloud does not have support for exposing this type of network storage to an end-user. If you want users to have access to this type of storage, you must configure it yourself.

### Choosing storage back-ends
If you wish to support object storage, block storage, or both, you need to select a software package to serve as the back-end. Here is a list of storage solutions that are currently supported by OpenStack.

This guide focuses on open-source technologies that can be used to implement object storage or block storage in an OpenStack cloud on top of commodity hardware. They include:

* Swift: object storage (default for object storage)
* LVM: block storage (default for block storage)
* Ceph: object storage and block storage
* Gluster: object storage and file storage (for shared storage live migration)
* ZFS: block storage
* Sheepdog: block storage

If you want to support shared storage live migration, you'll need to configure a network file system. Any file system will do, but possible options include:

 * NFS
 * GlusterFS
 * MooseFS
 * CephFS
 * Lustre

First, you need to decide whether you want to support object storage in your cloud. The two common use cases for providing object storage in a compute cloud are:

 * To provide users with a persistent storage mechanism
 * As a reliable data store for virtual machine images

If you decide to support object storage in your compute cloud, the three  options supported by OpenStack are Swift, Ceph, and Gluster UFO (Swift with Gluster back-end). Both projects emerged from cloud computing provider companies (Swift from Rackspace, Ceph from DreamHost), and both are currently deployed for production.

Swift is the official OpenStack Object Store implementation. It is a mature technology that has been used for several years in production by Rackspace as the technology behind Rackspace Cloud Files. As Swift is highly scalable, it is  well-suited to managing petabytes of storage. It was also designed to support replication across different geographic locations.

Ceph is a scalable storage solution that replicates data across commodity storage nodes. Ceph was originally developed by one of the founders of DreamHost and is currently used in production there. Ceph was designed to expose different types of storage interfaces to the end-user: it supports object storage, block storage, and file system interfaces, although the file system interface is not yet considered production-ready. Ceph supports the same API as Swift for object storage, can be used as a back-end for Cipher block storage, as well as back-end storage for Glance images. Ceph supports "thin provisioning", implemened using copy-on-write. This can be useful when booting from volume because a new volume can be provisioned very quickly. However, Ceph does not support keystone-based authentication, so if you want to provide users with access to object storage, you will need to create new accounts for them with your Ceph deployment in addition to the accounts they have with your OpenStack cloud.

As of Gluster version 3.3, you can use Gluster to consolidate your object storage and file storage into one unified file and object storage solution, which is called Gluster UFO. Gluster UFO uses a customizes version of Swift that uses Gluster as the back-end. The main advantage of using Gluster UFO over regular Swift is if you also want to support a distributed file system, either to support shared storage live migration or to provide it as a separate service to your end-users.

LVM refers to Logical Volume Manager, a Linux-based system that provides an abstraction layer on top of physical disks to expose logical volumes to the operating system. The LVM (Logical Volume Manager) backend implements block storage as LVM logical partitions. On each host that will house block storage, an administrator must initially create a volume group dedicated to Cinder volumes. Blocks will be created from LVM logical volumes. LVM does not provide any replication. Typically, administrators configure  RAID on nodes that use LVM as block storage, in order to protect against failures of individual hard drives. However, this does not protect against a failure of the entire host. If you wish to be able to support replication of block storage backend data across multiple hosts with LVM, you'll also need to configure DRBD.

The Solaris backend implements blocks as ZFS entities. ZFS is a file system that also has functionality of a volume manager. This is unlike on a Linux system, where there is a separation of volume manager (LVM) and file system (e.g., ext3, ext4, xfs, btrfs). It has a number of advantages over ext4. ZFS was originally developed by Sun Microsystem for Solaris. Today, when an open-source based system is deployed on commodity hardware that uses ZFS, it typically runs on an operating system that derives from Solaris such as Illumos or OpenIndiana, although it is also natively supported by FreeBSD. There is a [Linux port of ZFS][zfsonlinux], but it is not included in any of the standard Linux distributions, but the ZFS block storage backend does not currently support it. As with LVM, ZFS does not provide replication across hosts on its own, you need to add a replication solution on top of ZFS if your cloud needs to be able to handle storage node failures.

Sheepdog is a recent project that aims to provide block storage for KVM-based instances, wth support for replication across hosts.

If you decide to support both object and block storage, we recommend choosing from one of the following options:

 * Swift for object storage, LVM for block storage  (default configuration)
 * Ceph for object and block storage
 * Gluster UFO for object storage

If you decide to deploy object storage, your main decision point is deciding between deploying Swift and Ceph. The comparison information below is based on a [blog post written by Dmitry Ukov of Mirantis][mirantis-blog-swift-ceph-comparison] and [a Q&A session from Mirantis][mirantis-blog-ceph-better-performance].

Swift's advantages are  better integration with OpenStack (keystone-based authentication, works with OpenStack dashboard interface) better support for multi-datacenter deployment through support of asynchronous eventual consistentcy replication. Ceph's advantages are that it gives the administrator more fine-grained control over data distribution and replication strategies, enables you to consolidate your object and block storage, enables very fast provisioning of boot-from-volume instances using thin provisioning, has better performance than Swift, and supports a distributed filesystem interface (though this interface is [not yet recommended][cephfs-not-production] for use in production deployment by the Ceph project).

Therefore, if you eventually plan on distributing your storage cluster across datacenters,  if you need unified accounts for your users for both compute and object storage, or if you want to control your object storage with the OpenStack dashboard, you should consider Swift.  If you wish to manage your object and block storage within a single system, or if you wish to support fast  boot-from-volume, you should consider Ceph.  If you wish to manage your object and file storage within a single, you should consider Gluster UFO.

We don't recommend ZFS unless you have previous experience with deploying ZFS, or you are willing to deploy a different operating system. If you wish to deploy ZFS, we recommend using Illumos, OpenIndiana, or FreeBSD, because we do not know if the Linux port of ZFS is stable enough for production. We don't yet recommend Sheepdog for a production cloud, because its authors at NTT Labs consider Sheepdog as an experimental technology.

In addition to the open-source technologies, there are a number of propietary technologies that Cinder supports as back-ends for implementing block storage. See the vendor websites for more details on these solutions:

* IBM Storwize V7000 unified storage system
* IBM XIV Storage System series
* NetApp onTap devices
* SolidFire high performance SSD storages
* NexentaStor Appliance

### Where to locate the storage

Once you have decided on back-ends for your object storage and block storage, you need to decide where you want to locate them. The two basic options are:

* Dedicated storage hosts
* Compute and storage on the same host

Many operators use separate compute and storage hosts. Compute services and storage services have different requirements: compute hosts typically require more CPU and RAM than storage hosts. Therefore, for a fixed budget, it makes sense to have different configurations for your compute nodes and your storage nodes, with . Also, you use separate compute and storage hosts, then you can treat your compute hosts as "stateless". This simplifies maintenance for the compute hosts: as long as you don't have any instances currently running on a compute host, you can take it offline or wipe it completely without having any effect on the rest of your cloud.

Finally, Swift and Ceph have replication features that occasionally require CPU-intensive activity, and so it's best to not run these sorts of processes on compute nodes.

However, if you are more restricted in the number of physical hosts you have available for creating your cloud, and so you want to be able to dedicate as many of your hosts as possible to running virtual machines, it makes sense to run compute and storage on the same machines. In this case, the compute nodes will occasionally see increased compute load due to Swift or Ceph activity.

If you decide to have separate compute hosts and storage hosts, and you support both object storage and block storage, you also need to decide whether you should mix object storage and block storage on the same nodes, or have dedicated object storage nodes and block storage nodes. For example, if you are using Swift for object storage and LVM for block storage,

## Networking: Quantum or Nova-network
The most recent release of OpenStack, Folsom, included a new networking component, called Quantum, which is designed to eventually replace the nova-network service. However, nova-network is still present in Folsom, and will be present in the next release, Grizzly.

We recommend adopting Quantum for networking, as nova-network is likely to become deprecated in the future.  The exception is if you need to the performance of multi-host mode. Quantum doesn't support that yet, which means you can bottleneck on the control node.

## Live migration

Another decision that an administrator needs to make is whether or not to support live migration. To support live migration requires that the instance files (in /var/lib/nova/instances) are stored on a distributed file system (e.g., NFS, Gluster) that is mounted by all of the compute hosts, and that the nova accounts on each compute hosts are configured to allow passwordless ssh using public key authentication.


## Example architectures

This section describes examples of how you might deploy OpenStack.

### "Basic" architecture

The first example we call a "basic" architecture.

This architecture involves the following node types:

 * Cloud controller node (1)
 * Network controller node (1)
 * Compute nodes (many)
 * Block storage nodes (many)
 * Object storage nodes (>3)

There is a single cloud controller node which hosts the API endpoints, as well as the database server and the message queue server. There is a separate network controller node that runs the DHCP server for VM instances, and  L3/NAT forwarding to support access to the OpenStack metadata service and floating IPs.

Hypervisor: KVM

Supported features:

 * Object storage
 * Block storage (volumes)
 * LVM-backed instances
 * Multiple tenant isolation
 * Floating IPs
 * block-based migration

TODO: Add links to descriptions of feature where appropriate


Technologies used:
 * MySQL
 * RabbitMQ
 * Keystone
 * Swift with keystone authentication
 * Glance with Swift backend
 * Cinder with LVM backend
 * Quantum with Open vSwitch backend

Cloud controller:

 * RabbitMQ
 * MySQL
 * keystone
 * glance-api
 * glance-registry
 * nova-api
 * nova-scheduler
 * quantum-server
 * cinder-api
 * cinder-scheduler
 * swift-proxy-server
 * horizon

Network node:

 * quantum-openvswitch-plugin
 * quantum-l3-agent
 * quantum-dhcp-agent

Compute nodes:

 * nova-compute
 * libvirt
 * kvm
 * open-iscsi
 * quantum-openvswitch-plugins

Block storge nodes:

* LVM
* TGT

Object storage nodes:

 * swift-account
 * swift-container
 * swft-object

To optimize performance: XFS file system, no RAID configuration on the drives

Performance requirements:

 * [Swift system requirements][swift-system-requirements]

### "Compact"

A "compact" architecture assumes that you want to evaluate the same type of services as in the "default" architecture, but you are very limited in the number of physical nodes you have access to.

This architecture involves the following node types:
 * Cloud controller + network controller node (1)
 * Compute + block + object storage (many)

In this architecture, the cloud controller node and network controller node are combined into a single node.

All of the other nodes are a combination of compute, block storage, and object storage.

### Ceph for object and block storage

Hypervisor: KVM

Supported features:

 * object storage
 * block storage
 * multiple tenant isolation
 * floating IPs

Technologies used:

 * MySQL
 * RabbitMQ
 * Keystone
 * Swift with keystone authentication
 * Glance with Swift backend
 * Cinder with LVM backend
 * Quantum with Open vSwitch backend

Cloud controller:

 * RabbitMQ
 * MySQL
 * keystone
 * glance-api
 * glance-registry
 * nova-api
 * nova-scheduler
 * quantum-server
 * cinder-api
 * cinder-scheduler
 * horizon
 * apache
 * memcache
 * radosgw

Network node:

 * quantum-openvswitch-plugin
 * quantum-l3-agent
 * quantum-dhcp-agent

Compute nodes:

 * nova-compute
 * libvirt
 * kvm
 * open-iscsi
 * quantum-openvswitch-plugins
 * ceph-mon

Storge nodes (object storage daemons):

* ceph-osd (one instance per disk)

## Case studies

This section describes some actual deployment architectures.

*TBD*


[install]: http://docs.openstack.org/install
[hsm]: http://wiki.openstack.org/HypervisorSupportMatrix
[zfsonlinux]: http://zfsonlinux.org
[quantum-plugins]: http://docs.openstack.org/folsom/openstack-network/admin/content/flexibility.html
[mirantis-blog-swift-ceph-comparison]: http://www.mirantis.com/blog/object-storage-openstack-cloud-swift-ceph/
[mirantis-blog-ceph-better-performance]: http://www.mirantis.com/blog/questions-and-answers-about-storage-as-a-service-with-openstack-cloud/
[cephfs-not-production]: http://ceph.com/docs/master/faq/
[swift-system-requirements]: http://docs.openstack.org/folsom/openstack-object-storage/admin/content/object-storage-system-requirements.html
