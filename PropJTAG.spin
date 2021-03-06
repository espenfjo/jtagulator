{{
+-------------------------------------------------+
| JTAG/IEEE 1149.1                                |
| Interface Object                                |
|                                                 |
| Author: Joe Grand                               |                     
| Copyright (c) 2013-2018 Grand Idea Studio, Inc. |
| Web: http://www.grandideastudio.com             |
|                                                 |
| Distributed under a Creative Commons            |
| Attribution 3.0 United States license           |
| http://creativecommons.org/licenses/by/3.0/us/  |
+-------------------------------------------------+

Program Description:

This object provides the low-level communication interface for JTAG/IEEE 1149.1
(http://en.wikipedia.org/wiki/Joint_Test_Action_Group). 

JTAG routines based on Silicon Labs' Application Note AN105: Programming FLASH
through the JTAG Interface (https://www.silabs.com/documents/public/application-
notes/an105.pdf). 

Usage: Call Config first to properly set the desired JTAG pinout and clock speed
 
}}


CON
{{ IEEE Std. 1149.1 2001
   TAP Signal Descriptions

   +-----------+----------------------------------------------------------------------------------------+
   |    Name   |                                   Description                                          |
   +-----------+----------------------------------------------------------------------------------------+
   |    TDI    |    Test Data Input: Serial input for instructions and data received by the test logic. |
   |           |    Data is sampled on the rising edge of TCK.                                          |
   +-----------+----------------------------------------------------------------------------------------+ 
   |    TDO    |    Test Data Output: Serial output for instructions and data sent from the test logic. |
   |           |    Data is shifted on the falling edge of TCK.                                         |
   +-----------+----------------------------------------------------------------------------------------+
   |           |    Test Port Clock: Synchronous clock for the test logic that accompanies any data     |
   |    TCK    |    transfer. Data on the TDI is sampled by the target on the rising edge, data on TDO  |
   |           |    is output by the target on the falling edge.                                        |
   +-----------+----------------------------------------------------------------------------------------+
   |    TMS    |    Test Mode Select: Used in conjunction with TCK to navigate through the state        |
   |           |    machine. TMS is sampled on the rising edge of TCK.                                  | 
   +-----------+----------------------------------------------------------------------------------------+
   |           |    Test Port Reset: Optional signal for asynchronous initialization of the test logic. |
   |    TRST#  |    Some targets intentionally hold TRST# low to keep JTAG disabled. If so, the pin     |
   |           |    will need to be located and pulled high. This object assumes TRST# assertion (if    |
   |           |    required) is done in advance by the top object.                                     |
   +-----------+----------------------------------------------------------------------------------------+
 }}

 {{ IEEE Std. 1149.1 2001
    TAP Controller
 
    The movement of data through the TAP is controlled by supplying the proper logic level to the
    TMS pin at the rising edge of consecutive TCK cycles. The TAP controller itself is a finite state
    machine that is capable of 16 states. Each state contains a link in the operation sequence necessary
    to manipulate the data moving through the TAP.

    TAP Notes:
    1. Data is valid on TDO beginning with the falling edge of TCK on entry into the
       Shift_DR or Shift_IR states. TDO goes "push-pull" on this TCK falling edge and remains "push-pull"
       until the TCK rising edge.
    2. Data is not shifted in from TDI on entry into Shift_DR or Shift_IR.    
    3. Data is shifted in from TDI on exit of Shift_IR and Shift_DR.
 }}


CON
  MAX_DEVICES_LEN      =  32       ' Maximum number of devices allowed in a single JTAG chain

  MIN_IR_LEN           =  2        ' Minimum length of instruction register per IEEE Std. 1149.1
  MAX_IR_LEN           =  32       ' Maximum length of instruction register
  MAX_IR_CHAIN_LEN     =  MAX_DEVICES_LEN * MAX_IR_LEN  ' Maximum total length of JTAG chain w/ IR selected
  
  MAX_DR_LEN           =  1024      ' Maximum length of data register

  
VAR
  long TDI, TDO, TCK, TMS, TCK_DELAY       ' JTAG globals (must stay in this order)


OBJ
 

PUB Config(tdi_pin, tdo_pin, tck_pin, tms_pin, tck_speed)
{
  Set JTAG configuration
  Parameters : TDI, TDO, TCK, TMS channels and TCK clock speed provided by top object
}
  longmove(@TDI, @tdi_pin, 4)                ' Move passed variables into globals for use in this object
  TCK_DELAY := DelayTable[tck_speed-1]       ' Look up actual waitcnt delay value for the specified clock speed
      
  ' Set direction of JTAG pins
  ' Output
  dira[TDI] := 1                          
  dira[TCK] := 1          
  dira[TMS] := 1

  ' Input 
  dira[TDO] := 0

  ' Ensure TCK starts low for pulsing
  outa[TCK] := 0               

 
PUB Detect_Devices : num
{
  Performs a blind interrogation to determine how many devices are connected in the JTAG chain.

  In BYPASS mode, data shifted into TDI is received on TDO delayed by one clock cycle. We can
  force all devices into BYPASS mode, shift known data into TDI, and count how many clock
  cycles it takes for us to see it on TDO.

  Leaves the TAP in the Run-Test-Idle state.

  Based on http://www.fpga4fun.com/JTAG3.html

  Returns    : Number of JTAG/IEEE 1149.1 devices in the chain (if any)
}
  Restore_Idle                ' Reset TAP to Run-Test-Idle
  Enter_Shift_IR              ' Enter Shift IR state

  ' Force all devices in the chain (if they exist) into BYPASS mode using opcode of all 1s
  outa[TDI] := 1              ' Output data bit HIGH
  repeat MAX_IR_CHAIN_LEN - 1 ' Send lots of 1s to account for multiple devices in the chain and varying IR lengths
    TCK_Pulse

  outa[TMS] := 1              ' Go to Exit1 IR
  TCK_Pulse

  outa[TMS] := 1              ' Go to Update IR, new instruction in effect
  TCK_Pulse

  outa[TMS] := 1              ' Go to Select DR Scan
  TCK_Pulse

  outa[TMS] := 0              ' Go to Capture DR Scan
  TCK_Pulse    

  outa[TMS] := 0              ' Go to Shift DR Scan
  TCK_Pulse
                          
  repeat MAX_DEVICES_LEN      ' Send 1s to fill DRs of all devices in the chain (In BYPASS mode, DR length = 1 bit)
    TCK_Pulse 

  ' We are now in BYPASS mode with all DR set
  ' Send in a 0 on TDI and count until we see it on TDO
  outa[TDI] := 0              ' Output data bit LOW
  repeat num from 0 to MAX_DEVICES_LEN - 1 
    if (ina[TDO] == 0)          ' If we have received our 0, it has propagated through the entire chain (one clock cycle per device in the chain)
      quit                        '  Exit loop (num gets returned)
    TCK_Pulse

  if (num > MAX_DEVICES_LEN - 1)  ' If no 0 is received, then no devices are in the chain
    num := 0

  outa[TMS] := 1
  TCK_Pulse                   ' Go to Exit1 DR

  outa[TMS] := 1
  TCK_Pulse                   ' Go to Update DR, new data in effect

  outa[TMS] := 0
  TCK_Pulse                   ' Go to Run-Test-Idle


PUB Detect_IR_Length : num 
{
  Performs an interrogation to determine the instruction register length of the target device.
  Limited in length to MAX_IR_LEN.
  Assumes a single device in the JTAG chain.
  Leaves the TAP in the Run-Test-Idle state.

  Returns    : Length of the instruction register
}
  Restore_Idle                ' Reset TAP to Run-Test-Idle
  Enter_Shift_IR              ' Go to Shift IR

  ' Flush the IR
  outa[TDI] := 0              ' Output data bit LOW
  repeat MAX_IR_LEN - 1       ' Since the length is unknown, send lots of 0s
    TCK_Pulse

  ' Once we are sure that the IR is filled with 0s
  ' Send in a 1 on TDI and count until we see it on TDO
  outa[TDI] := 1              ' Output data bit HIGH
  repeat num from 0 to MAX_IR_LEN - 1 
    if (ina[TDO] == 1)          ' If we have received our 1, it has propagated through the entire instruction register
      quit                        '  Exit loop (num gets returned)
    TCK_Pulse

  if (num > MAX_IR_LEN - 1) or (num < MIN_IR_LEN)  ' If no 1 is received, then we are unable to determine IR length
    num := 0
    
  outa[TMS] := 1
  TCK_Pulse                   ' Go to Exit1 IR

  outa[TMS] := 1
  TCK_Pulse                   ' Go to Update IR, new instruction in effect

  outa[TMS] := 0
  TCK_Pulse                   ' Go to Run-Test-Idle


PUB Detect_DR_Length(value) : num | len
{
  Performs an interrogation to determine the data register length of the target device.
  The selected data register will vary depending on the the instruction.
  Limited in length to MAX_DR_LEN.
  Assumes a single device in the JTAG chain.
  Leaves the TAP in the Run-Test-Idle state.

  Parameters : value = Opcode/instruction to be sent to TAP
  Returns    : Length of the data register
}
  len := Detect_IR_Length          ' Determine length of TAP IR
  Send_Instruction(value, len)     ' Send instruction/opcode
  Enter_Shift_DR                   ' Go to Shift DR

  ' At this point, a specific DR will be selected, so we can now determine its length.
  ' Flush the DR
  outa[TDI] := 0              ' Output data bit LOW
  repeat MAX_DR_LEN - 1       ' Since the length is unknown, send lots of 0s
    TCK_Pulse

  ' Once we are sure that the DR is filled with 0s
  ' Send in a 1 on TDI and count until we see it on TDO
  outa[TDI] := 1              ' Output data bit HIGH
  repeat num from 0 to MAX_DR_LEN - 1 
    if (ina[TDO] == 1)          ' If we have received our 1, it has propagated through the entire data register
      quit                        '  Exit loop (num gets returned)
    TCK_Pulse
      
  if (num > MAX_DR_LEN - 1)   ' If no 1 is received, then we are unable to determine DR length
    num := 0
    
  outa[TMS] := 1
  TCK_Pulse                   ' Go to Exit1 DR

  outa[TMS] := 1
  TCK_Pulse                   ' Go to Update DR, new data in effect

  outa[TMS] := 0
  TCK_Pulse                   ' Go to Run-Test-Idle

  
PUB Bypass_Test(num, bPattern) : value
{
  Run a Bypass through every device in the chain. 
  Leaves the TAP in the Run-Test-Idle state.

  Parameters : num = Number of devices in JTAG chain
               bPattern = 32-bit value to shift into TDI
  Returns    : 32-bit value received from TDO
}
  Restore_Idle                ' Reset TAP to Run-Test-Idle
  Enter_Shift_IR              ' Enter Shift IR state

  ' Force all devices in the chain (if they exist) into BYPASS mode using opcode of all 1s
  outa[TDI] := 1              ' Output data bit HIGH
  repeat (num * MAX_IR_LEN)   ' Send in 1s
    TCK_Pulse

  outa[TMS] := 1              ' Go to Exit1 IR
  TCK_Pulse

  outa[TMS] := 1              ' Go to Update IR, new instruction in effect
  TCK_Pulse

  outa[TMS] := 0
  TCK_Pulse                   ' Go to Run-Test-Idle

  ' Shift in the 32-bit pattern
  ' Each device in the chain delays the data propagation by one clock cycle
  value := Send_Data(bPattern, 32 + num)
  value ><= 32                ' Bitwise reverse since LSB came in first (we want MSB to be first)


PUB Get_Device_IDs(num, idptr) | data, i
{
  Retrieves the JTAG device ID from each device in the chain. 
  Leaves the TAP in the Run-Test-Idle state.

  The Device Identification register (if it exists) should be immediately available
  in the DR after power-up of the target device or after TAP reset.

  Parameters : num = Number of devices in JTAG chain
               idptr = Pointer to memory in which to store the received 32-bit device IDs (must be large enough for all IDs) 
}
{{ IEEE Std. 1149.1 2001
   Device Identification Register

   MSB                                                                          LSB
   +-----------+----------------------+---------------------------+--------------+
   |  Version  |      Part Number     |   Manufacturer Identity   |   Fixed (1)  |
   +-----------+----------------------+---------------------------+--------------+
      31...28          27...12                  11...1                   0
}}
  Restore_Idle                      ' Reset TAP to Run-Test-Idle
  Enter_Shift_DR                    ' Go to Shift DR

  outa[TDI] := 1                    ' Output data bit HIGH (TDI is ignored when shifting IDCODE, but we need to set a default state)

  repeat i from 0 to (num - 1)      ' For each device in the chain...
    data := Shift_Array(0, 32)       ' Receive 32-bit value from DR (should be IDCODE if exists), leaves the TAP in Exit1 DR
    data ><= 32                      ' Bitwise reverse since LSB came in first (we want MSB to be first)
    long[idptr][i] := data           ' Store it in hub memory
    
    outa[TMS] := 0
    TCK_Pulse                        ' Go to Pause DR
  
    outa[TMS] := 1
    TCK_Pulse                        ' Go to Exit2 DR

    outa[TMS] := 0
    TCK_Pulse                        ' Go to Shift DR

  Restore_Idle                      ' Reset TAP to Run-Test-Idle


PUB Send_Instruction(instruction, num_bits) : ret_value
{
    This method loads the supplied instruction of num_bits length into the target's Instruction Register (IR).
    The return value is the num_bits length value read from the IR (limited to 32 bits).
    TAP must be in Run-Test-Idle state before being called.
    Leaves the TAP in the Run-Test-Idle state.
}
{{ IEEE Std. 1149.1 2001
   Instructions
   
   Instruction Register/Opcode length vary per device family
   IR length must >= 2

   +-----------+-------------+----------+-----------------------------------------------------------------------+
   |    Name   |  Required?  |  Opcode  |                          Description                                  |
   +-----------+-------------+----------+-----------------------------------------------------------------------+
   |   BYPASS  |      Y      |  All 1s  |   Bypass on-chip system logic. Allows serial data to be transferred   |
   |           |             |          |   from TDI to TDO without affecting operation of the IC.              |
   +-----------+-------------+----------+-----------------------------------------------------------------------+
   |   SAMPRE  |      Y      |  Varies  |   Used for controlling (preload) or observing (sample) the signals at |
   |           |             |          |   device pins. Enables the boundary scan register.                    |
   +-----------+-------------+----------+-----------------------------------------------------------------------+
   |   EXTEST  |      Y      |  All 0s  |   Places the IC in external boundary test mode. Used to test device   |
   |           |             |          |   interconnections. Enables the boundary scan register.               |
   +-----------+-------------+----------+-----------------------------------------------------------------------+
   |   INTEST  |      N      |  Varies  |   Used for static testing of internal device logic in a single-step   |
   |           |             |          |   mode. Enables the boundary scan register.                           |
   +-----------+-------------+----------+-----------------------------------------------------------------------+
   |   RUNBIST |      N      |  Varies  |   Places the IC in a self-test mode and selects a user-specified data |
   |           |             |          |   register to be enabled.                                             |
   +-----------+-------------+----------+-----------------------------------------------------------------------+
   |   CLAMP   |      N      |  Varies  |   Sets the IC outputs to logic levels as defined in the boundary scan |
   |           |             |          |   register. Enables the bypass register.                              |
   +-----------+-------------+----------+-----------------------------------------------------------------------+
   |   HIGHZ   |      N      |  Varies  |   Sets all IC outputs to a disabled (high impedance) state. Enables   |
   |           |             |          |   the bypass register.                                                |
   +-----------+-------------+----------+-----------------------------------------------------------------------+
   |   IDCODE  |      N      |  Varies  |   Enables the 32-bit device identification register. Does not affect  |
   |           |             |          |   operation of the IC.                                                |
   +-----------+-------------+----------+-----------------------------------------------------------------------+
   |  USERCODE |      N      |  Varies  |   Places user-defined information into the 32-bit device              |
   |           |             |          |   identification register. Does not affect operation of the IC.       |
   +-----------+-------------+----------+-----------------------------------------------------------------------+
}}    
  Enter_Shift_IR

  ret_value := Shift_Array(instruction, num_bits)

  outa[TMS] := 1
  TCK_Pulse                   ' Go to Update IR, new instruction in effect

  outa[TMS] := 0
  TCK_Pulse                   ' Go to Run-Test-Idle


PUB Send_Data(data, num_bits) : ret_value
{
    This method shifts num_bits of data into the target's Data Register (DR). 
    The return value is the num_bits length value read from the DR (limited to 32 bits).
    TAP must be in Run-Test-Idle state before being called.
    Leaves the TAP in the Run-Test-Idle state.
}   
  Enter_Shift_DR

  ret_value := Shift_Array(data, num_bits)

  outa[TMS] := 1
  TCK_Pulse                   ' Go to Update DR, new data in effect

  outa[TMS] := 0
  TCK_Pulse                   ' Go to Run-Test-Idle


PRI Shift_Array(array, num_bits) : ret_value | i 
{
    Shifts an array of bits into the TAP while reading data back out.
    This method is called when the TAP state machine is in the Shift_DR or Shift_IR state.
}
  ret_value := 0
    
  repeat i from 1 to num_bits
    outa[TDI] := array & 1    ' Output data to target, LSB first
    array >>= 1 

    ret_value <<= 1     
    ret_value |= ina[TDO]     ' Receive data, shift order depends on target
     
    if (i == num_bits)        ' If at final bit...
      outa[TMS] := 1            ' Go to Exit1
      
    TCK_Pulse

       
PRI Enter_Shift_DR      ' 
{
    Move TAP to the Shift-DR state.
    TAP must be in Run-Test-Idle state before being called.
}
  outa[TMS] := 1
  TCK_Pulse                   ' Go to Select DR Scan

  outa[TMS] := 0
  TCK_Pulse                   ' Go to Capture DR

  outa[TMS] := 0
  TCK_Pulse                   ' Go to Shift DR
  

PRI Enter_Shift_IR  
{
    Move TAP to the Shift-IR state.
    TAP must be in Run-Test-Idle state before being called.
}
  outa[TMS] := 1
  TCK_Pulse                   ' Go to Select DR Scan

  outa[TMS] := 1
  TCK_Pulse                   ' Go to Select IR Scan

  outa[TMS] := 0
  TCK_Pulse                   ' Go to Capture IR

  outa[TMS] := 0
  TCK_Pulse                   ' Go to Shift IR
    
  
PUB Restore_Idle
{
    Resets the TAP to the Test-Logic-Reset state from any unknown state by transitioning through the state machine.
    TMS is held high for five consecutive TCK clock periods.
    Leaves the TAP in the Run-Test-Idle state.
}
  outa[TMS] := 1              ' TMS high
  repeat 5
    TCK_Pulse

  outa[TMS] := 0             
  TCK_Pulse                   ' Go to Run-Test-Idle

  
PRI TCK_Pulse
{
    Generate one TCK pulse.
    Expects TCK to be low upon being called.
}
    outa[TCK] := 1              ' TCK high (target samples TMS and TDI on rising edge of TCK, affects TAP) 
    waitcnt(TCK_DELAY + cnt)
    outa[TCK] := 0              ' TCK low (TDO is now valid on the falling edge of TCK) 
    waitcnt(TCK_DELAY + cnt)
  

DAT
' Look-up table to correlate actual JTAG (TCK) clock speed (1kHz to 22kHz) to waitcnt delay value
'                    1      2      3      4     5     6     7     8     9     10    11    12    13    14    15    16    17    18   19   20   21   22
DelayTable    long   38677, 18667, 12005, 8634, 6667, 5316, 4365, 3650, 3092, 2656, 2284, 1980, 1731, 1513, 1323, 1148, 1003, 869, 754, 652, 556, 460

