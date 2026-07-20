import cocotb
from cocotb.triggers import RisingEdge, Timer, First, with_timeout
from cocotbext.axi import AxiBus, AxiMaster

from random import randint

class AxiWrapper:

    def __init__(self, dut, i):

        self._log = dut._log
        self._name = f"kal {i}"

        self.awready = dut.awready[i]
        self.awvalid = dut.awvalid[i]
        self.awid = dut.awid[i]
        self.awaddr = dut.awaddr[i]
        self.awlen = dut.awlen[i]
        self.awsize = dut.awsize[i]
        self.awburst = dut.awburst[i]
        self.wready = dut.wready[i]
        self.wvalid = dut.wvalid[i]
        self.wdata = dut.wdata[i]
        self.wstrb = dut.wstrb[i]
        self.wlast = dut.wlast[i]
        self.bvalid = dut.bvalid[i]
        self.bid = dut.bid[i]
        self.bready = dut.bready[i]
        self.arready = dut.arready[i]
        self.arvalid = dut.arvalid[i]
        self.arid = dut.arid[i]
        self.araddr = dut.araddr[i]
        self.arlen = dut.arlen[i]
        self.arsize = dut.arsize[i]
        self.arburst = dut.arburst[i]
        self.rvalid = dut.rvalid[i]
        self.rid = dut.rid[i]
        self.rdata = dut.rdata[i]
        self.rlast = dut.rlast[i]
        self.rready = dut.rready[i]

@cocotb.test
async def test(dut):
    await RisingEdge(dut.rst_n)
    axi_master = [AxiMaster(AxiBus.from_prefix(AxiWrapper(dut, i), ""), dut.clk, dut.rst_n, reset_active_level=False) for i in range(dut.DMA_CHANNEL_COUNT.value)]
    await RisingEdge(dut.clk)

    task_awaiter = RisingEdge(dut.reg_acc_test_done)
    timeout = Timer(1_000_000, unit='ns')

    result = await First(
        timeout,
        task_awaiter
    )

    assert result is not timeout, "The design has hung!"

    for i in range(dut.PIPELINE_CAPACITY.value.to_unsigned()):
        for j in range(dut.DMA_CHANNEL_COUNT.value):
            await with_timeout(axi_master[j].read(randint(0, (2**32-1) // 16) * 16, randint(0, 255), i), 1_000_000, 'ns')

    for i in range(dut.PIPELINE_CAPACITY.value.to_unsigned()):
        for j in range(dut.DMA_CHANNEL_COUNT.value):
            await with_timeout(axi_master[j].read(randint((2**32) // 16, (2**64-1) // 16) * 16, randint(0, 255), i), 1_000_000, 'ns')