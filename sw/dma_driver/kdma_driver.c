#include <linux/types.h>
#include <linux/module.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/pci.h>
#include <linux/device.h>
#include <linux/dma-mapping.h>
#include <linux/io-64-nonatomic-lo-hi.h>
#include <linux/delay.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/wait.h>
#include <linux/mutex.h>
#include <asm/param.h>

#define DRIVER_NAME "hdlnocgen_c5p_driver"
#define DMA_BUFFER_SIZE 4194304

DECLARE_WAIT_QUEUE_HEAD(dma_wq);

uint16_t vendor, device;

struct hdlnocgen_device {
    // Task mutex
    struct mutex task_read_mutex;
    struct mutex task_write_mutex;

    // Device variables
    uint64_t b0_start, b0_size;
    uint64_t b2_start, b2_size;
    void __iomem *bar0_ptr, *bar2_ptr; // Remapped BARs
    uint32_t bdf;

    // Device file variables
    dev_t driver_dev_nr;
    struct cdev driver_cdev;
    struct class *driver_class;

    // DMA control variables
    uint16_t dma_channel_count;
    int dma_irq_index[16];
    uint8_t dma_irq_rd_flags[16];
    uint8_t dma_irq_wr_flags[16];
    uint64_t dma_cap_addrs[17];
    int user_irq_index[16];
    uint8_t user_irq_flags[16];
    void *cpu_addr[16];
    dma_addr_t dma_handle[16];
};

static struct hdlnocgen_device *device_array[16] = { NULL };
static uint8_t hdlnocgen_device_count = 0;

static char *hdlnocgen_devnode(const struct device *dev, umode_t *mode) {
    if (!mode) {
        return NULL;
    }
    if (!dev) {
        return NULL;
    }
    *mode = 0666;
    return NULL;
}

// IRQ assertion counter
uint16_t irq_fired = 0;

// Error handling globs
int err, err_index = 0;


static ssize_t read_from_pci(struct file *filp, char __user *user_buf, size_t len, loff_t *off) {
    int dev_ind;

    for (int i = 0; i < 16; i++) {
        if (MAJOR(device_array[i]->driver_dev_nr) == MAJOR(filp->f_inode->i_rdev)) {
            dev_ind = i;
            break;
        }
        if (i == 15) {
            printk(KERN_ERR "hdlnocgen_c5p_driver: No MAJOR match, bad device files\n");
            return -1;
        }
    }

    int channel = MINOR(filp->f_inode->i_rdev);

    //printk(KERN_INFO "hdlnocgen_c5p_driver: Read request from device %d BDF %x MINOR %u\n", dev_ind, device_array[dev_ind]->bdf, channel);


    if (channel == (device_array[dev_ind]->dma_channel_count)) {
        int retval = len - 1;
        if (retval == -1) {
            return retval;
        }
        if (*off > 16) {
            return -EINVAL;
        }
        retval += copy_to_user(user_buf, (device_array[dev_ind]->user_irq_flags)+*off, 1);

        return retval;
    }
    else if (channel == (device_array[dev_ind]->dma_channel_count)+1) {
        int retval = len - 4;
        if (retval < 0) {
            return retval;
        }
        uint32_t read_value = ioread32((device_array[dev_ind]->bar2_ptr)+0x2000+*off);
        retval += copy_to_user(user_buf, &read_value, 4);

        return retval;
    }
    else if (channel == (device_array[dev_ind]->dma_channel_count)+2) {
        int retval = len - 4;
        if (retval < 0) {
            return retval;
        }
        if ((uint64_t)*off > 0xC) {
            return -EINVAL;
        }
        uint32_t read_value = ioread32((device_array[dev_ind]->bar2_ptr)+0x0000+*off);
        retval += copy_to_user(user_buf, &read_value, 4);

        return retval;
    }

    if (len > DMA_BUFFER_SIZE) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Requested to read %lu bytes, which is larger than size of DMA buffer (%llu bytes)\n", len, (uint64_t)DMA_BUFFER_SIZE);
        return -ENOMEM;
    }

    mutex_lock(&(device_array[dev_ind]->task_read_mutex));
    uint32_t task_fifo_free = ioread32((device_array[dev_ind]->bar2_ptr) + 0x4);
    if (task_fifo_free == 0) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Read from DMA channel %d fail - no free spaces in DMAWR-FIFO\n", channel);
        mutex_unlock(&(device_array[dev_ind]->task_read_mutex));
        return -ENOMEM;
    }
    iowrite64((((uint64_t)len) << 32) | (uint64_t)*off, (device_array[dev_ind]->bar2_ptr) + 0x1000 + channel*0x10);
    mutex_unlock(&(device_array[dev_ind]->task_read_mutex));
    //printk(KERN_INFO "hdlnocgen_c5p_driver: Read from DMA channel %d command sent\n", channel);


    uint32_t jiffies = wait_event_interruptible_timeout(dma_wq, (device_array[dev_ind]->dma_irq_rd_flags[channel]) == 1, HZ*2);
    if (!jiffies) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Read from DMA device %d BDF %x MINOR %u timeout\n", dev_ind, device_array[dev_ind]->bdf, channel);
        uint32_t irq_status = ioread32((device_array[dev_ind]->bar2_ptr) + ((device_array[dev_ind]->dma_cap_addrs[channel]) + 0x20));
        printk(KERN_ERR "hdlnocgen_c5p_driver: irq status %u\n", irq_status);
        printk(KERN_ERR "hdlnocgen_c5p_driver: irq fired %u times\n", irq_fired);
        return -1;
    }
    (device_array[dev_ind]->dma_irq_rd_flags[channel]) = 0;

    //printk(KERN_INFO "hdlnocgen_c5p_driver: Read from DMA channel %d finished successfully\n", channel);

    uint64_t not_copied = copy_to_user(user_buf, (device_array[dev_ind]->cpu_addr[channel]) + (uint64_t)*off, len);

    if (not_copied) {
        printk(KERN_WARNING "hdlnocgen_c5p_driver: %llu bytes of data failed to copy to kernel\n", not_copied);
    }

    return not_copied;
}

static ssize_t write_to_pci(struct file *filp, const char __user *user_buf, size_t len, loff_t *off) {
    int dev_ind;

    for (int i = 0; i < 16; i++) {
        if (MAJOR(device_array[i]->driver_dev_nr) == MAJOR(filp->f_inode->i_rdev)) {
            dev_ind = i;
            break;
        }
        if (i == 15) {
            printk(KERN_ERR "hdlnocgen_c5p_driver: No MAJOR match, bad device files\n");
            return -1;
        }
    }

    int channel = MINOR(filp->f_inode->i_rdev);

    //printk(KERN_INFO "hdlnocgen_c5p_driver: Write request to device %d BDF %x MINOR %u\n", dev_ind, device_array[dev_ind]->bdf, channel);

    if (channel == (device_array[dev_ind]->dma_channel_count)) {
        int retval = len - 1;
        if (retval == -1) {
            return 0;
        }
        if (*off > 16) {
            return -EINVAL;
        }
        retval += copy_from_user((device_array[dev_ind]->user_irq_flags)+*off, user_buf, 1);

        return retval;
    }
    else if (channel == (device_array[dev_ind]->dma_channel_count)+1) {
        int retval = len - 4;
        if (retval < 0) {
            return retval;
        }
        uint32_t write_value;
        retval += copy_from_user(&write_value, user_buf, 4);
        iowrite32(write_value, (device_array[dev_ind]->bar2_ptr)+0x2000+*off);

        return retval;
    }
    else if (channel == (device_array[dev_ind]->dma_channel_count)+2) {
        int retval = len - 4;
        if (retval < 0) {
            return retval;
        }
        if ((uint64_t)*off > 0xC) {
            return -EINVAL;
        }
        uint32_t write_value;
        retval += copy_from_user(&write_value, user_buf, 4);
        iowrite32(write_value, (device_array[dev_ind]->bar2_ptr)+0x0000+*off);

        return retval;
    }

    if (len > DMA_BUFFER_SIZE) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Requested to write %lu bytes, which is larger than size of DMA buffer (%llu bytes)\n", len, (uint64_t)DMA_BUFFER_SIZE);
        return -ENOMEM;
    }

    uint64_t not_copied = copy_from_user((device_array[dev_ind]->cpu_addr[channel]) + (uint64_t)*off, user_buf, len);

    if (not_copied) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: %llu bytes of data failed to copy to kernel. No transfer\n", not_copied);
        return not_copied;
    }

    mutex_lock(&(device_array[dev_ind]->task_write_mutex));
    uint32_t task_fifo_free = ioread32((device_array[dev_ind]->bar2_ptr) + 0x8);
    uint32_t dmawr_status = ioread32((device_array[dev_ind]->bar2_ptr) + ((device_array[dev_ind]->dma_cap_addrs[channel]) + 0x18));
    if (dmawr_status != 0) {
        printk(KERN_INFO "hdlnocgen_c5p_driver: device %d BDF %x MINOR %u dmawr status %u\n", dev_ind, device_array[dev_ind]->bdf, channel, dmawr_status);
    }
    if (task_fifo_free == 0) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Write to DMA channel %d fail - no free spaces in DMARD-FIFO\n", channel);
        mutex_unlock(&(device_array[dev_ind]->task_write_mutex));
        return -ENOMEM;
    }
    fsleep(10);
    iowrite64((((uint64_t)(len-not_copied)) << 32) | (uint64_t)*off, (device_array[dev_ind]->bar2_ptr) + 0x1008 + channel*0x10);
    mutex_unlock(&(device_array[dev_ind]->task_write_mutex));
    //printk(KERN_INFO "hdlnocgen_c5p_driver: Write to DMA channel %d command sent\n", channel);

    uint32_t jiffies = wait_event_interruptible_timeout(dma_wq, (device_array[dev_ind]->dma_irq_wr_flags[channel]) == 1, HZ*2);
    if (!jiffies) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Write to DMA device %d BDF %x MINOR %u timeout\n", dev_ind, device_array[dev_ind]->bdf, channel);
        uint32_t irq_status = ioread32((device_array[dev_ind]->bar2_ptr) + ((device_array[dev_ind]->dma_cap_addrs[channel]) + 0x20));
        printk(KERN_ERR "hdlnocgen_c5p_driver: irq status %u\n", irq_status);
        uint32_t dmawr_status = ioread32((device_array[dev_ind]->bar2_ptr) + ((device_array[dev_ind]->dma_cap_addrs[channel]) + 0x18));
        printk(KERN_ERR "hdlnocgen_c5p_driver: dmawr status %u\n", dmawr_status);
        printk(KERN_ERR "hdlnocgen_c5p_driver: irq fired %u times\n", irq_fired);
        return -1;
    }
    (device_array[dev_ind]->dma_irq_wr_flags[channel]) = 0;

    //printk(KERN_INFO "hdlnocgen_c5p_driver: Write to DMA channel %d finished successfully\n", channel);

    return not_copied;
}


static struct file_operations fops = {
	.read = read_from_pci,
    .write = write_to_pci
};


static struct pci_device_id my_driver_id_table[] = {
    { PCI_DEVICE(0x1172, 0xd800) },
    { PCI_DEVICE(0x1172, 0x00ff) },
    { PCI_DEVICE(0x10ee, 0x7024) },
    {0,}
};
MODULE_DEVICE_TABLE(pci, my_driver_id_table);

static int hdlnocgen_dma_probe(struct pci_dev *pdev, const struct pci_device_id *ent);

static void hdlnocgen_dma_remove(struct pci_dev *pdev);


static struct pci_driver hdlnocgen_dma_driver = {
    .name = "hdlnocgen_c5p_dma",
    .id_table = my_driver_id_table,
    .probe = hdlnocgen_dma_probe,
    .remove = hdlnocgen_dma_remove
};



static irqreturn_t dma_finish(int irq, void *dev) {
    int dev_ind = -1;
    int irq_index = -1;

    for (int i = 0; i < 16; i++) {
        if (!device_array[i]) {
            continue;
        }
        for (int j = 0; j < (device_array[i]->dma_channel_count); j++) {
            if ((device_array[i]->dma_irq_index[j]) == irq) {
                dev_ind = i;
                irq_index = j;
            }
        }
    }

    uint32_t irq_status = ioread32((device_array[dev_ind]->bar2_ptr) + ((device_array[dev_ind]->dma_cap_addrs[irq_index]) + 0x20));
    if (((irq_status & 0x4) >> 2) == 1) {
        iowrite32(0x1, (device_array[dev_ind]->bar2_ptr) + ((device_array[dev_ind]->dma_cap_addrs[irq_index]) + 0x20));
        (device_array[dev_ind]->dma_irq_rd_flags[irq_index]) = 1;
    }
    if (((irq_status & 0x8) >> 3) == 1) {
        iowrite32(0x2, (device_array[dev_ind]->bar2_ptr) + ((device_array[dev_ind]->dma_cap_addrs[irq_index]) + 0x20));
        (device_array[dev_ind]->dma_irq_wr_flags[irq_index]) = 1;
    }

    irq_fired += 1;

    wake_up_all(&dma_wq);
    return IRQ_HANDLED;
}

static irqreturn_t user_msix_pend(int irq, void *dev) {
    int dev_ind;
    int irq_index;

    for (int i = 0; i < 16; i++) {
        if (!device_array[i]) {
            continue;
        }
        for (int j = 0; j < (device_array[i]->dma_channel_count); j++) {
            if ((device_array[i]->user_irq_index[j]) == irq) {
                dev_ind = i;
                irq_index = j;
                (device_array[dev_ind]->user_irq_flags[i]) = 1;
            }
        }
    }

    return IRQ_HANDLED;
}

static int hdlnocgen_dma_probe(struct pci_dev *pdev, const struct pci_device_id *ent) {
    pci_read_config_word(pdev, PCI_VENDOR_ID, &vendor);
    pci_read_config_word(pdev, PCI_DEVICE_ID, &device);
    printk(KERN_INFO "hdlnocgen_c5p_driver: Device vid: 0x%X\n", vendor);
    printk(KERN_INFO "hdlnocgen_c5p_driver: Device pid: 0x%X\n", device);
    printk(KERN_INFO "hdlnocgen_c5p_driver: BDF: %02x:%02x.%01x\n", pdev->bus->number, PCI_SLOT(pdev->devfn), PCI_FUNC(pdev->devfn));

    if (hdlnocgen_device_count == 16) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: 16 devices already initialized. Failed to register\n");
        return -ENOMEM;
    }

    printk(KERN_INFO "hdlnocgen_c5p_driver: Creating struct for the device and placing it in the array...\n");
    struct hdlnocgen_device *device_struct = kzalloc(sizeof(struct hdlnocgen_device), GFP_KERNEL);
    if (!device_struct) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Failed to allocate device struct\n");
        return -ENOMEM;
    }
    for (int i = 0; i < 16; i++) {
        if (!device_array[i]) {
            device_array[i] = device_struct;
            hdlnocgen_device_count++;
            printk(KERN_INFO "hdlnocgen_c5p_driver: New array index %d, device count %d, BDF: %x\n", i, hdlnocgen_device_count, (pdev->bus->number << 12) | (PCI_SLOT(pdev->devfn) << 4) | PCI_FUNC(pdev->devfn));
            break;
        } else {
            printk(KERN_INFO "hdlnocgen_c5p_driver: Array index %d, BDF: %x\n", i, device_array[i]->bdf);
        }
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: Success!\n");

    device_struct->bdf = (pdev->bus->number << 12) | (PCI_SLOT(pdev->devfn) << 4) | PCI_FUNC(pdev->devfn);
    
    mutex_init(&(device_struct->task_read_mutex));
    mutex_init(&(device_struct->task_write_mutex));

    // PCIe memory enable
    err = pci_enable_device_mem(pdev);
    if (err) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Failed to enable PCIe device's memory\n");
        goto destroy_mutex;
    }

    // PCIe device BAR[0] req
    err = pci_request_region(pdev, 0, DRIVER_NAME);
    if (err) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Failed to reserve BAR0\n");
        goto pci_disable;
    }
    // PCIe device BAR[2] req
    err = pci_request_region(pdev, 2, DRIVER_NAME);
    if (err) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Failed to reserve BAR2\n");
        goto pci_release_bar0;
    }

    // Get BAR[0] addresses
    device_struct->b0_start = pci_resource_start(pdev, 0);
    device_struct->b0_size = pci_resource_len(pdev, 0);
    printk(KERN_INFO "hdlnocgen_c5p_driver: BAR[0]: 0x%llx-0x%llx\n", device_struct->b0_start, device_struct->b0_start + device_struct->b0_size - 1);
    // Get BAR[2] addresses
    device_struct->b2_start = pci_resource_start(pdev, 2);
    device_struct->b2_size = pci_resource_len(pdev, 2);
    printk(KERN_INFO "hdlnocgen_c5p_driver: BAR[2]: 0x%llx-0x%llx\n", device_struct->b2_start, device_struct->b2_start + device_struct->b2_size - 1);

    // Remap BARs to memory
    device_struct->bar0_ptr = ioremap(device_struct->b0_start, device_struct->b0_size);
    if (!(device_struct->bar0_ptr)) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Failed to ioremap BAR[0]...\n");
        err = -ENOMEM;
        goto pci_release_bar2;
    }
    device_struct->bar2_ptr = ioremap(device_struct->b2_start, device_struct->b2_size);
    if (!(device_struct->bar2_ptr)) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Failed to ioremap BAR[2]...\n");
        err = -ENOMEM;
        goto unmap_bar0;
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: ioremapped BAR[0] to %p\n", device_struct->bar0_ptr);
    printk(KERN_INFO "hdlnocgen_c5p_driver: ioremapped BAR[2] to %p\n", device_struct->bar2_ptr);

    printk(KERN_INFO "hdlnocgen_c5p_driver: Extracting configuration info...\n");
    device_struct->dma_channel_count = ioread32(device_struct->bar2_ptr) & 0xFFFF;
    printk(KERN_INFO "hdlnocgen_c5p_driver: Extracting done. This DMA has %hu channels\n", device_struct->dma_channel_count);

    // Register MSIs
    printk(KERN_INFO "hdlnocgen_c5p_driver: Allocating %hu DMA and %hu user interrupts\n", device_struct->dma_channel_count, device_struct->dma_channel_count);
    err = pci_alloc_irq_vectors(pdev, (device_struct->dma_channel_count)*2, (device_struct->dma_channel_count)*2, PCI_IRQ_MSIX);
    if (err < 0) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Failed to register PCIe interrupts\n");
        goto unmap_bar2;
    }
    else if (err != (device_struct->dma_channel_count)*2) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Failed to allocate PCIe interrupts - %hu interrupts required, but %d alocated\n", (device_struct->dma_channel_count)*2, err);
        goto msi_free;
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: Allocated %d interrupts using MSIXs\n", err);


    // DMA address mask setup
    err = dma_set_mask_and_coherent(&(pdev->dev), DMA_BIT_MASK(64));
    if (err) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Failed to set DMA mask\n");
        goto msi_free;
    }

    // Register DMA IRQ handlers
    for (int i = 0; i < (device_struct->dma_channel_count); i++) {
        // Set IRQ handler
        (device_struct->dma_irq_index[i]) = pci_irq_vector(pdev, i);
        printk(KERN_INFO "hdlnocgen_c5p_driver: DMA IRQ for channel %d is %d\n", i, (device_struct->dma_irq_index[i]));

        err = request_irq((device_struct->dma_irq_index[i]), dma_finish, IRQF_TRIGGER_RISING, DRIVER_NAME, NULL);
        if (err) {
            printk(KERN_INFO "hdlnocgen_c5p_driver: Failed to register DMA IRQ handler for channel %d\n", i);
            goto unregister_irq;
        }
        printk(KERN_INFO "hdlnocgen_c5p_driver: Registered IRQ handler for DMA channel %d\n", i);
        printk(KERN_INFO "hdlnocgen_c5p_driver: Register read data - Interrupt address low %x\n", ioread32(device_struct->bar0_ptr + i*16));
        printk(KERN_INFO "hdlnocgen_c5p_driver: Register read data - Interrupt address high %x\n", ioread32(device_struct->bar0_ptr + i*16 + 4));
        err_index = i + 1;
    }

    // Register user IRQ handlers
    for (int i = (device_struct->dma_channel_count); i < (device_struct->dma_channel_count)*2; i++) {
        // Set IRQ handler
        (device_struct->user_irq_index[i-(device_struct->dma_channel_count)]) = pci_irq_vector(pdev, i);
        printk(KERN_INFO "hdlnocgen_c5p_driver: User IRQ for channel %d is %d\n", i-(device_struct->dma_channel_count), (device_struct->user_irq_index[i-(device_struct->dma_channel_count)]));

        err = request_irq((device_struct->user_irq_index[i-(device_struct->dma_channel_count)]), user_msix_pend, IRQF_TRIGGER_RISING, DRIVER_NAME, NULL);
        if (err) {
            printk(KERN_INFO "hdlnocgen_c5p_driver: Failed to register user IRQ handler for channel %d\n", i-(device_struct->dma_channel_count));
            goto unregister_user_irq;
        }
        printk(KERN_INFO "hdlnocgen_c5p_driver: Registered IRQ handler for user channel %d\n", i-(device_struct->dma_channel_count));
        printk(KERN_INFO "hdlnocgen_c5p_driver: Register read data - Interrupt address low %x\n", ioread32(device_struct->bar0_ptr + i*16));
        printk(KERN_INFO "hdlnocgen_c5p_driver: Register read data - Interrupt address high %x\n", ioread32(device_struct->bar0_ptr + i*16 + 4));
        err_index = i + 1;
    }

    // Allocate DMA buffers
    uint32_t next_struct_addr = (ioread32(device_struct->bar2_ptr) & 0xFFFF0000) >> 16;
    printk(KERN_INFO "hdlnocgen_c5p_driver: Channel 0 struct addr is 0x%x\n", next_struct_addr);
    (device_struct->dma_cap_addrs[0]) = next_struct_addr;

    for (int i = 0; i < device_struct->dma_channel_count; i++) {
        (device_struct->cpu_addr[i]) = dma_alloc_coherent(&(pdev->dev), DMA_BUFFER_SIZE, &(device_struct->dma_handle[i]), GFP_KERNEL);
        if (!(device_struct->cpu_addr[i])) {
            printk(KERN_ERR "hdlnocgen_c5p_driver: Failed to allocate %llu bytes for DMA buffer channel %d\n", (uint64_t)DMA_BUFFER_SIZE, i);
            err = ENOENT;
            goto free_dma;
        }
        printk(KERN_INFO "hdlnocgen_c5p_driver: Created %d bytes of dma bytes. Channel - %d, CPU addr - 0x%p, DMA addr - 0x%llx\n", DMA_BUFFER_SIZE, i, (device_struct->cpu_addr[i]), (device_struct->dma_handle[i]));

        iowrite32((device_struct->dma_handle[i]), (device_struct->bar2_ptr) + next_struct_addr + 4);
        iowrite32((device_struct->dma_handle[i]) >> 32, (device_struct->bar2_ptr) + next_struct_addr + 8);
        printk(KERN_INFO "hdlnocgen_c5p_driver: Wrote DMA addr for channel %d\n", i);
        printk(KERN_INFO "hdlnocgen_c5p_driver: Register read data - DMA addr low %x\n", ioread32((device_struct->bar2_ptr) + next_struct_addr + 4));
        printk(KERN_INFO "hdlnocgen_c5p_driver: Register read data - DMA addr high %x\n", ioread32((device_struct->bar2_ptr) + next_struct_addr + 8));

        next_struct_addr = ioread32((device_struct->bar2_ptr) + next_struct_addr);
        printk(KERN_INFO "hdlnocgen_c5p_driver: Channel %d struct addr is 0x%x\n", i+1, next_struct_addr);
        (device_struct->dma_cap_addrs[i+1]) = next_struct_addr;

        err_index = i + 1;
    }

    // Driver device setup
    err = alloc_chrdev_region(&(device_struct->driver_dev_nr), 0, MINORMASK + 1, "hdlnocgen_c5p_cdev"); // get major and minor numbers allocated
    if (err) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Failed to reserve major and minor numbers\n");
        goto free_dma;
    }
    cdev_init(&(device_struct->driver_cdev), &fops);
    (device_struct->driver_cdev).owner = THIS_MODULE;

    err = cdev_add(&(device_struct->driver_cdev), (device_struct->driver_dev_nr), MINORMASK + 1);
    if (err) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Failed to create cdev\n");
        goto free_driver_dev_nr;
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: Registered cdev with Major %d starting with Minor %d\n", MAJOR(device_struct->driver_dev_nr), MINOR(device_struct->driver_dev_nr)); // register cdev under these numbers

    char *class_name;
    class_name = kasprintf(GFP_KERNEL, "hdlnocgen_%05x_class", device_struct->bdf);
    if (!class_name) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Failed to create name for the class\n");
        goto free_driver_dev_nr;
    }

    device_struct->driver_class = class_create(class_name);
    if (!(device_struct->driver_class)) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Could not create class %s\n", class_name);
        err = -ENOMEM;
        goto delete_driver_cdev;
    }
    device_struct->driver_class->devnode = hdlnocgen_devnode;
    printk(KERN_INFO "hdlnocgen_c5p_driver: Created class %s\n", class_name);
    
    kfree(class_name);

    for (int i = 0; i < device_struct->dma_channel_count; i++) {
        if (!device_create(device_struct->driver_class, &(pdev->dev), (device_struct->driver_dev_nr)+i, NULL, "hdlnocgen_%05x_%d", device_struct->bdf, i)) {
            printk(KERN_ERR "hdlnocgen_c5p_driver: Could not create device file hdlnocgen_%05x_%d", device_struct->bdf, i);
            err = -ENOMEM;
            goto destroy_device_file;
        }
        printk(KERN_INFO "hdlnocgen_c5p_driver: Created device file hdlnocgen_%05x_%d", device_struct->bdf, i); // register cdev under these numbers

        err_index = i + 1;
    }

    if (!device_create(device_struct->driver_class, &(pdev->dev), (device_struct->driver_dev_nr)+(device_struct->dma_channel_count), NULL, "hdlnocgen_%05x_user_irq", device_struct->bdf)) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Could not create device file hdlnocgen_%05x_user_irq", device_struct->bdf);
        err = -ENOMEM;
        goto destroy_device_file;
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: Created device file hdlnocgen_%05x_user_irq", device_struct->bdf);

    if (!device_create(device_struct->driver_class, &(pdev->dev), (device_struct->driver_dev_nr)+(device_struct->dma_channel_count)+1, NULL, "hdlnocgen_%05x_env_csr", device_struct->bdf)) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Could not create device file hdlnocgen_%05x_env_csr", device_struct->bdf);
        err = -ENOMEM;
        goto destroy_user_irq_file;
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: Created device file hdlnocgen_%05x_env_csr", device_struct->bdf);

    if (!device_create(device_struct->driver_class, &(pdev->dev), (device_struct->driver_dev_nr)+(device_struct->dma_channel_count)+2, NULL, "hdlnocgen_%05x_dma_csr", device_struct->bdf)) {
        printk(KERN_ERR "hdlnocgen_c5p_driver: Could not create device file hdlnocgen_%05x_dma_csr", device_struct->bdf);
        err = -ENOMEM;
        goto destroy_env_csr_file;
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: Created device file hdlnocgen_%05x_dma_csr", device_struct->bdf);

    // Set PCIe as master
    pci_set_master(pdev);
    printk(KERN_INFO "hdlnocgen_c5p_driver: Bus mastered by PCIe device\n");

    printk(KERN_INFO "hdlnocgen_c5p_driver: dma_irq_index: \n");
    for (int i = 0; i < 16; i++) {
        printk(KERN_CONT "%d ", device_struct->dma_irq_index[i]);
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: dma_irq_rd_flags: \n");
    for (int i = 0; i < 16; i++) {
        printk(KERN_CONT "%d ", device_struct->dma_irq_rd_flags[i]);
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: dma_irq_wr_flags: \n");
    for (int i = 0; i < 16; i++) {
        printk(KERN_CONT "%d ", device_struct->dma_irq_wr_flags[i]);
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: dma_cap_addrs: \n");
    for (int i = 0; i < 16; i++) {
        printk(KERN_CONT "%llx ", device_struct->dma_cap_addrs[i]);
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: user_irq_index: \n");
    for (int i = 0; i < 16; i++) {
        printk(KERN_CONT "%d ", device_struct->user_irq_index[i]);
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: user_irq_flags: \n");
    for (int i = 0; i < 16; i++) {
        printk(KERN_CONT "%d ", device_struct->user_irq_flags[i]);
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: cpu_addr: \n");
    for (int i = 0; i < 16; i++) {
        printk(KERN_CONT "%p ", device_struct->cpu_addr[i]);
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: dma_handle: \n");
    for (int i = 0; i < 16; i++) {
        printk(KERN_CONT "%llx ", device_struct->dma_handle[i]);
    }

    for (int i = 0; i < 16; i++) {
        if (!device_array[i]) {
            printk(KERN_INFO "hdlnocgen_c5p_driver: Array index %d empty\n", i);
        } else {
            printk(KERN_INFO "hdlnocgen_c5p_driver: Array index %d, BDF: %x\n", i, device_array[i]->bdf);
        }
    }

    return 0;

destroy_env_csr_file:
    device_destroy(device_struct->driver_class, (device_struct->driver_dev_nr)+(device_struct->dma_channel_count)+1);
destroy_user_irq_file:
    device_destroy(device_struct->driver_class, (device_struct->driver_dev_nr)+(device_struct->dma_channel_count));
destroy_device_file:
    for (int i = 0; i < err_index; i++) {
        device_destroy(device_struct->driver_class, (device_struct->driver_dev_nr)+i);
    }
    err_index = device_struct->dma_channel_count;
//delete_driver_class:
	class_unregister(device_struct->driver_class);
	class_destroy(device_struct->driver_class);
delete_driver_cdev:
	cdev_del(&(device_struct->driver_cdev));
free_driver_dev_nr:
    unregister_chrdev_region(device_struct->driver_dev_nr, MINORMASK + 1);
free_dma:
    for (int i = 0; i < err_index; i++) {
        dma_free_coherent(&(pdev->dev), DMA_BUFFER_SIZE, (device_struct->cpu_addr[i]), (device_struct->dma_handle[i]));
    }
    err_index = (device_struct->dma_channel_count);
unregister_user_irq:
    for (int i = 0; i < err_index; i++) {
        free_irq((device_struct->user_irq_index[i]), NULL);
    }
    err_index = (device_struct->dma_channel_count);
unregister_irq:
    for (int i = 0; i < err_index; i++) {
        free_irq((device_struct->dma_irq_index[i]), NULL);
    }
    err_index = (device_struct->dma_channel_count);
msi_free:
    pci_free_irq_vectors(pdev);
unmap_bar2:
    iounmap(device_struct->bar2_ptr);
unmap_bar0:
    iounmap(device_struct->bar0_ptr);
pci_release_bar2:
    pci_release_region(pdev, 2);
pci_release_bar0:
    pci_release_region(pdev, 0);
pci_disable:
    pci_disable_device(pdev);
destroy_mutex:
    mutex_destroy(&(device_struct->task_write_mutex));
    mutex_destroy(&(device_struct->task_read_mutex));

    for (int i = 0; i < 16; i++) {
        if (device_array[i] == device_struct) {
            device_array[i] = NULL;
            break;
        }
    }
    kfree(device_struct);
    hdlnocgen_device_count--;

    return err;
}

static void hdlnocgen_dma_remove(struct pci_dev *pdev) {
    printk(KERN_INFO "hdlnocgen_c5p_driver: PCIe device removal...\n");

    int dev_arr_id;

    for (int i = 0; i < 16; i++) {
        if (!device_array[i]) {
            continue;
        }

        if (device_array[i]->bdf == ((pdev->bus->number << 12) | (PCI_SLOT(pdev->devfn) << 4) | PCI_FUNC(pdev->devfn))) {
            dev_arr_id = i;
            printk(KERN_INFO "hdlnocgen_c5p_driver: Device %d in the array\n", i);
            break;
        }
        
        if (i == 15) {
            printk(KERN_ERR "hdlnocgen_c5p_driver: BDF: %x. Device not found in the array. Bad exit\n", ((pdev->bus->number << 12) | (PCI_SLOT(pdev->devfn) << 4) | PCI_FUNC(pdev->devfn)));
            return;
        }
    }
    pci_clear_master(pdev);
    printk(KERN_INFO "hdlnocgen_c5p_driver: PCIe device unmastered\n");

    device_destroy(device_array[dev_arr_id]->driver_class, (device_array[dev_arr_id]->driver_dev_nr)+(device_array[dev_arr_id]->dma_channel_count)+2);
    printk(KERN_INFO "hdlnocgen_c5p_driver: Deleted file hdlnocgen_c5p_dma_csr\n");

    device_destroy(device_array[dev_arr_id]->driver_class, (device_array[dev_arr_id]->driver_dev_nr)+(device_array[dev_arr_id]->dma_channel_count)+1);
    printk(KERN_INFO "hdlnocgen_c5p_driver: Deleted file hdlnocgen_c5p_env_csr\n");

    device_destroy(device_array[dev_arr_id]->driver_class, (device_array[dev_arr_id]->driver_dev_nr)+(device_array[dev_arr_id]->dma_channel_count));
    printk(KERN_INFO "hdlnocgen_c5p_driver: Deleted file hdlnocgen_c5p_user_irq\n");

    for (int i = 0; i < device_array[dev_arr_id]->dma_channel_count; i++) {
        device_destroy(device_array[dev_arr_id]->driver_class, (device_array[dev_arr_id]->driver_dev_nr)+i);
        printk(KERN_INFO "hdlnocgen_c5p_driver: Deleted file hdlnocgen_c5p%d\n", i);
    }

	class_unregister(device_array[dev_arr_id]->driver_class);
	class_destroy(device_array[dev_arr_id]->driver_class);
    printk(KERN_INFO "hdlnocgen_c5p_driver: Deleted cdev class\n");

	cdev_del(&(device_array[dev_arr_id]->driver_cdev));
    printk(KERN_INFO "hdlnocgen_c5p_driver: Deleted driver cdev\n");

    unregister_chrdev_region(device_array[dev_arr_id]->driver_dev_nr, MINORMASK + 1);
    printk(KERN_INFO "hdlnocgen_c5p_driver: Unregistered devnr region\n");

    for (int i = 0; i < (device_array[dev_arr_id]->dma_channel_count); i++) {
        dma_free_coherent(&(pdev->dev), DMA_BUFFER_SIZE, (device_array[dev_arr_id]->cpu_addr[i]), (device_array[dev_arr_id]->dma_handle[i]));
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: DMA buffers freed\n");

    for (int i = 0; i < (device_array[dev_arr_id]->dma_channel_count); i++) {
        free_irq(device_array[dev_arr_id]->dma_irq_index[i], NULL);
    }
    printk(KERN_INFO "hdlnocgen_c5p_driver: Freed IRQ handlers\n");

    for (int i = 0; i < (device_array[dev_arr_id]->dma_channel_count); i++) {
        free_irq(device_array[dev_arr_id]->user_irq_index[i], NULL);
    }

    pci_free_irq_vectors(pdev);
    printk(KERN_INFO "hdlnocgen_c5p_driver: PCIe MSIXs released\n");

    iounmap(device_array[dev_arr_id]->bar2_ptr);
    printk(KERN_INFO "hdlnocgen_c5p_driver: BAR[2] unmapped\n");

    iounmap(device_array[dev_arr_id]->bar0_ptr);
    printk(KERN_INFO "hdlnocgen_c5p_driver: BAR[0] unmapped\n");

    pci_release_region(pdev, 2);
    printk(KERN_INFO "hdlnocgen_c5p_driver: BAR[2] released\n");

    pci_release_region(pdev, 0);
    printk(KERN_INFO "hdlnocgen_c5p_driver: BAR[0] released\n");

    pci_disable_device(pdev);
    printk(KERN_INFO "hdlnocgen_c5p_driver: PCIe device disabled\n");

    mutex_destroy(&(device_array[dev_arr_id]->task_write_mutex));
    mutex_destroy(&(device_array[dev_arr_id]->task_read_mutex));
    printk(KERN_INFO "hdlnocgen_c5p_driver: Mutexes destroyed\n");

    printk(KERN_INFO "hdlnocgen_c5p_driver: User IRQs pending: ");
    for (int i = 0; i < (device_array[dev_arr_id]->dma_channel_count); i++) {
        printk(KERN_CONT "%d ", (device_array[dev_arr_id]->user_irq_flags[i]));
    }

    kfree(device_array[dev_arr_id]);
    device_array[dev_arr_id] = NULL;
    hdlnocgen_device_count--;

    for (int i = 0; i < 16; i++) {
        if (!device_array[i]) {
            printk(KERN_INFO "hdlnocgen_c5p_driver: Array index %d empty\n", i);
        } else {
            printk(KERN_INFO "hdlnocgen_c5p_driver: Array index %d, BDF: %x\n", i, device_array[i]->bdf);
        }
    }

}


static int __init init_hdlnocgen_dma_driver (void) {

	return pci_register_driver(&hdlnocgen_dma_driver);
}

static void __exit cleanup_hdlnocgen_dma_driver (void) {

	pci_unregister_driver(&hdlnocgen_dma_driver);
}

module_init(init_hdlnocgen_dma_driver);
module_exit(cleanup_hdlnocgen_dma_driver);

MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("stargazer");
MODULE_DESCRIPTION("A PCIe DMA driver for a controller on a Terasic openVINO Starter kit devboard's FPGA");
