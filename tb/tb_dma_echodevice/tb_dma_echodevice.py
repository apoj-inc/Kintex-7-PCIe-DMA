import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
from cocotbext.axi import AxiBus, AxiWriteBus, AxiRam, AxiRamWrite

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
    dma_channel_count = dut.DMA_CHANNEL_COUNT.value

    await RisingEdge(dut.rst_n)
    await RisingEdge(dut.dut.dma_resetn)
    axi_ram = [AxiRam(AxiBus.from_prefix(AxiWrapper(dut, i), ""), dut.clk, dut.rst_n, size=2**48, reset_active_level=False) for i in range(dma_channel_count)]
    msix_ram = AxiRamWrite(AxiWriteBus.from_prefix(dut, "msix"), dut.clk, dut.rst_n, size=2**48, reset_active_level=False)
    
    await RisingEdge(dut.clk)
    
    for iter in range(2):
        for i in range(dma_channel_count):
            for j in range(16384):
                axi_ram[i].write_byte(0xF000_0000_0000 + i*0x4 + j, randint(0, 255))
        await RisingEdge(dut.check_mem)
        dut.check_mem.value = 0

    task_awaiter = RisingEdge(dut.test_done)
    timeout = Timer(1_000_000, unit='ns')

    result = await First(
        timeout,
        task_awaiter
    )

    assert result is not timeout, "The design has hung!"