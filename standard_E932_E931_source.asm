;****************************************************************************************************
;* GENERAL NOTES
;* =============
;* Project started with the help of dsm-ecu Yahoo group, thanks for the great info.
;* Most disassembly comments in this file by Christian, christi999@hotmail.com. 
;*
;* CPU
;* ----
;* The microcomputer chip used in the 1G DSM ECU seems to be a custom application 
;* built around the 6801 architecture, Check the 6801, 6803, 6301, 68HC11 at web sites 
;* such as alldatasheet.com, etc. 
;*
;* CPU clock frequency is assumed to be 2MHz, i.e. the instructions cycle time is 0.5us.
;*
;* Assembly binary verifications: 
;* ------------------------------
;*
;*    The 2 binaries produced without any customization ("enableCustom" definition is
;*    commented-out) have been verified to be identical to the E931 and E932 eprom 
;*    images at hand.
;*
;*    To check the validity of symbolic substitution, the entire code section and tables 
;*    was offset by $0200 using "codeOffset" and the corresponding binary was tested on
;*    my car (E932) without any problems for weeks. Additional tests were conducted by
;*    writing inline code in several part of the code and no adverse effect was ever noted.
;*
;*    To check the validity of symbolic substitution for ram addresses, every ram location
;*    starting at $0057 was offset by 1 (i.e. temp1 was at memory address $58 instead of 
;*    $57, etc) and the corresponding binary was tested on my car (E932) without any problems
;*    during car startup and engine revving. No additional test performed.
;*
;*    This means that the code can be modified inline and in most cases, ram memories can 
;*    be moved around by changing the label addresses. Note however that some groups of
;*    ram memories have to be moved in blocks because the code assumes they are contiguous.
;*    e.g. the temp1 to temp9 variables, the inj1_offT, inj3_offT, inj4_offT and inj2_offT
;*    variables, etc.
;*
;* Ram memory: 
;* -----------
;*    Memory from $0040 to $01bf is backed-up by battery, meaning it is preserved when the
;*    ECU is powered-off as long as battery power is supplied. However, memory from $0057 to
;*    $0190 is cleared to 0 by the code every time the ECU is powered-on. That can be however
;*    changed by modifying the code... Battery backup was checked by disabling memory reset using
;*    the "noRamReset"  and then check ram memory at $018f to see if it gets preserved after power 
;*    off/on cycle, and it did. During the test, $018f was used as a distance counter using 
;*    the reed switch.
;*
;* Comments: 
;* --------
;*   Some comments use variable names quite loosly. For instance, multi-byte variables
;*   such as [airCnt0:airCnt1:airCnt2] might be refered to as only airCnt0. airCnt0
;*   might therefore refer to the single byte airCnt0, to the 16 bit value 
;*   [airCnt0:airCnt1] or to the 24 bit complete variable, depending on the context.
;*
;*   Comments were added incrementally as my knowledge of code and variables
;*   increased. As new knowledge was learned, old comments were updated or corrected
;*   as much as possible but not necessarily all of them, so beware... In the end, the
;*   code is the only truth... Some small areas of the code were also never completly
;*   understood as a general understanding was reached and I did not care to go further
;*   e.g. airflow sensor active filter reset
;*
;* Opcodes: 
;* --------
;*    -cmpd: cmpd1 is used for some addressing modes instead of cmpd since 
;*           TASM does not support unusual mitsubishi ECU cmpd opcodes..   
;*
;*    -brclr: branch if ALL the given bits are clear
;*
;*    -brset: branch if ANY of the given bits are set (as opposed to usual 
;*            implementation of ALL bits set...)
;*
;*    -The addressing mode using Y indexing also implicitly
;*     modifies the y register. It seems that y is increased
;*     by 1 or 2 depending whether the instruction is a 8 bit
;*     or 16 bits operation... The following cases are confirmed
;*
;*         cmpa $00,y  -> y = y + 1 
;*         cmpb $00,y  -> y = y + 1 
;*         ldaa $00,y  -> y = y + 1
;*         suba $00,y  -> y = y + 1
;*         ldx  $00,y  -> y = y + 2
;*         std  $00,y  -> y = y + 2
;*
;*                
;* Telemark assembler:
;* --------------------
;*    This assembler does not provide warning messages when code assembles to
;*    the same memory space, e.g. you insert code in the middle of the file 
;*    which result in the rest of the code to be offset by N bytes. This
;*    results in the interrupt vector table to be overwritten. No warning 
;*    is given. The only way to know about it is to manually check the listing 
;*    file produced by the assembler. Check that the buffer space between 
;*    sections is all "$ff". Check that there is no code spilage over .org 
;*    statements. Check that the address space does not exceed $ffff. Use the 
;*    "codeOffset" at the beginnng of the file to correct the problem.
;*              
;*              
;* Fuel injector and coil power transistor control
;* ------------------------------------------------
;*    Although the 4 fuel injectors and the 2 coil power transistors are mapped to
;*    regular ports (port1, port2 and port5) which can be read to know the current
;*    state of these outputs, they are also mapped in hardware to output compare
;*    registers in order to activate or deactivate them at specific time instants.
;*    Writing to the ports might therefore not work unless the output compare 
;*    configuration registers are changed to disable harware control of these 
;*    outputs. This might not be possible unless an "output enable" bit exists,
;*    which I haven't found at this point...
;*    Another way to activate or deactivate them would be to use the output
;*    compare registers (as currently done by the ECU code) and provoke an 
;*    immediat output change.
;*
;*    Here is my current understanding of how injector scheduling works, not 
;*    everything is clear to me so don't take this as gospel...:
;*    The output compare registers for the fuel injectors seem to be at least double
;*    buffered and maybe triple buffered (see schedInjSim routine). That means that 
;*    up to 3 different output compare values can be written to t1_outCmpWr and t2_outCmpWr
;*    to activate or deactivate the injectors at those time instants. Each time a value
;*    is written to t1_outCmpWr or t2_outCmpWr, the corresponding injector state
;*    is also internally stored. That means that to activate injector #1 at time X,
;*    you would first reset bit 0 of t1_csr, corresponding to injector #1 and then
;*    write X to t1_outCmpWr. You could then immediately schedule the deactivation
;*    of injector #1 by setting bit 0 of t1_csr to 1 and then write the deactivation 
;*    time to t1_outCmpWr. When one of the output compare register stored value matches 
;*    the clock at t1t2_clk, the injector is activated/deactivated and the corresponding
;*    interrupt routine is called (if the interrupt mask is clear...) at outCompInt1 or 
;*    outCompInt2.
;*
;*    Here is my current understanding of how the coil power transistor scheduling 
;*    works, not everything is clear to me so don't take this as gospel...: t3_outCmpWr
;*    is the output compare register used to activate or deactivate the coil power 
;*    transistors (energize the coil and provoke ignition at the specified time instants)
;*    To energize the coil for cylinder 1 and 4 at time X you would write X to t3_outCmpWr 
;*    and reset(0) bit 2 of t3_csr0. At time X, t3_csr0.2 would be loaded into port5.1 
;*    which would energize the coil. t3_csr0.2 should not be changed until that happens.
;*    In the code, most of the time 2 successive values (the same one) are written to t3_outCmpWr 
;*    but there are some instances where only 1 value is written. My impression is that
;*    the first value serves to activate/deactivate the coil power transistor at the 
;*    specified instant while the second one only serves to generate an interrupt
;*    in order to call the outCompInt3 routine. Hence when only the coil need
;*    to be activated/deactivated without calling outCompInt3, you would only write 
;*    one value. If in addition you want to have outCompInt3 called when the coil 
;*    is energized/ignited, you would write two successive values (corresponding to the 
;*    same time...). This is all speculation of course... As for the 2 clocks at t3_clock1
;*    and t3_clock1, I assume they are connected to the same internal clock at 250KHz
;*    but might be input capture registers latched when one of the two output compare 
;*    at t3_outCmpWr is triggered??????? Again speculation, this is the part of the code
;*    I understand the least...
;*
;*
;* Timing diagram 
;* --------------          
;*
;* -4 cylinders = 2 rotations = 2 * 360degrees = 720 degrees
;*
;* -For sequential injection, fuel injection starts on the cas falling edge 
;*  i.e. cylinder #1 injection starts at -5 BTDC of #3 TDC
;*
;* -Simultaneous injection of all 4 injectors is performed when starting to 
;*  crank or starting a cold engine or during acceleration, check the tech manual
;*  and code for more details. Simultaneous injection starts on the 5deg BTDC
;*  cas signal except in the case of acceleration where it starts when an
;*  injector is deactivated and no other injector is active (i.e. at the 
;*  beginning of the time period where no injector is active)
;*
;* -Coil energization is usually scheduled (the energization time is loaded into
;*  the output compare register, energization will occur at the specified time)
;*  from the cas rising edge. Coil ignition can be scheduled when energization
;*  occurs (output compare interrupt) or on the cas falling edge depending on 
;*  the desired timing. Note however that coil energization can also be scheduled
;*  when ignition occurs on the preceeding cylinder. This would correspond to 
;*  scheduling ignition before the cas rising edge (at high rpm I assume). Coil
;*  energization can also be scheduled on the cas falling edge when the desired
;*  timing is high (e.g. 10deg ATDC). As this shows, there are several combinations 
;*  and the complexity of the code to handle the coil reflects that fact.
;*  
;*           
;*                         No 1 TDC         No 3 TDC          No 4 TDC          No 2 TDC
;*                            :                 :                 :                 :
;*                   ___________                         _____ 
;* TDC sensor       |           |                       |     |
;* signal           |         : |               :       |     |   :                 :
;*              ____|___________|_______________________|_____|________________________
;*  degrees        85           55                      85   15
;* (BTDC/ATDC)                :                 :                 :                 :
;*                    ______            ______            ______            ______ 
;* CAS sensor        |      |          |      |          |      |          |      |
;* signal            |      | :        |      | :        |      | :        |      | :
;*              _____|______|__________|______|__________|______|__________|______|____
;*  degrees          75     5 :       75      5 :       75      5 :        75     5 :
;*  (BTDC)                    :                 :                 :                 :
;*           
;*                            :                 :                 :                 : 
;*  No 1 cyl.     compression :   combustion    :    exhaust      :     intake      : compression
;*  No 3 cyl.       intake    :   compression   :   combustion    :     exhaust     :  intake     
;*  No 4 cyl.       exhaust   :     intake      :   compression   :    combustion   :  exhaust    
;*  No 2 cyl.     combustion  :     exhaust     :    intake       :    compression  : combustion  
;*           
;*           
;*           
;* Airflow calculations dependencies, more details in code
;* --------------------------------------------------------
;*           
;* masProc: airflow sensor interrupt, increases [airCntNew0:airCntNew1] 
;*    |     by airQuantum for every airflow sensor pulse received
;*    |
;*    | 
;*    |
;*    |--> [airCntNew0:airCntNew1]: Increased by airQuantum for every airflow sensor pulse
;*             |                    Reset and used as input to [airCnt0:airCnt1:airCnt2]
;*             |                    on every cas falling edge, i.e. air is counted twice
;*             |                    per rotation, once for every cylinder cycle... It can 
;*             |                    therefore be seen as the air count per cylinder.
;*             |
;*             |--> [airCnt0:airCnt1:airCnt2]: Filtered version of 256*[airCntNew0:airCntNew1]
;*                        |                    exponential averaging is used.
;*                        |
;*                        |
;*                        |
;*                        |--> mafraw16: 16 bit airflow sensor pulse frequency (mafraw16/10.24)Hz
;*                        |       |      mafraw16 = 8205*[airCnt0:airCnt1]/Tcas
;*                        |       |
;*                        |       |
;*                        |       |--> mafraw: 8 bit airflow sensor pulse frequency (6.25*mafraw)Hz
;*                        |                    mafraw: = mafraw16/64
;*                        |
;*                        |
;*                        |
;*                        |--> airVol16: Equals [airCnt0:airCnt1] * masScalar/65536
;*                        |       |
;*                        |       |
;*                        |       |
;*                        |       |--> airVol   : Equals airVol16/2
;*                        |       |--> airVolT  : Equals airVol16/2 * iatCompFact/128
;*                        |       |--> airVolTB : Equals airVol16/2 * iatCompFact/128 * baroFact/128
;*                        |       |--> airVolB  : Equals airVol16/2 * baroFact/128
;*                        |
;*                        |
;*                        |--> injPw: Injector pulse width in "normal" operation, 
;*                                    injPw = [airCnt0:airCnt1] * injFactor/256  + other corrections
;*
;*
;*
;* Discussion on MAS compensation factors
;* ---------------------------------------
;*
;*     Total airflow sensor compensation is made-up of:
;*     
;*          totMasComp(freq,iat,baro) = masComp + t_masComp(freq) + t_masLin(freq,iat,baro)
;*     
;*     where maxComp is a fixed offset ($64 for 1G and $40 for 2G) and t_masComp and t_masLin
;*     are table values interpolated from frequency, intake air temperature and barometric 
;*     pressure. t_masComp(freq) is basically compensation for the airflow sensor charcteristic
;*     curve as a function of frequency (to linearize the number of pulse per sec vs. the volume
;*     of air passing through the sensor) while t_masLin(freq,iat,baro) is a smaller factor
;*     probably compensating for temperature drift (electronic) and airflow characteristic 
;*     change as a function of air density???
;*     
;*     Assuming the following:
;*     
;*         -injComp     = 100% (for 260cc injectors at 36psi)
;*         -workFtrim   = 100%
;*         -o2FuelAdj   = 100%
;*         -iatCompFact = 100% (at 25.6degC)
;*         -baroFact    = 100% (~1 bar)
;*         -openLoopEnr = 100%
;*         -coldTempEnr = 100%
;*         -enrWarmup   = 0%
;*     
;*     
;*     Then the injector pulswidth is calculated by the ECU as (excluding deadtime)
;*     
;*         injPw(usec/cylinder) = numPulsePerCasInterrupts *$9c * totMasComp * 16/256
;*                              = numPulsePerCasInterrupts * totMasComp * 9.75
;*     
;*     If we also assume a 14.7 air to fuel ratio, Dair=1.18 air density (g/litre) at 25degC, 
;*     Dgas=0.775 fuel density (g/cc) then we would need 23900 usec of injection per 
;*     litre of air using the same 260cc at 36psi, working that factor into the equation, we 
;*     get
;*     
;*         injPw(usec/cylinder) = numPulsePerCasInterrupts * totMasComp * 9.75
;*                              = numPulsePerCasInterrupts * totMasComp/2452 * 2452 * 9.75 
;*                              = numPulsePerCasInterrupts * totMasComp/2452 * 23900usecOfInjection/litreOfAir
;*     
;*     This means that under the above assumptions, totMasComp/2452 has units of 
;*     litreOfAirPerAirflowSensorPulse. 
;*     
;*     The factor 2452 is similar to the one provided by J. Oberholtzer, I think. 
;*     The exact value must be somewhere in that range...
;*     
;*     masScalar is also used for maf compensation ($5e86,24198 for 1G, $7A03,31235 for 2g) 
;*     for controls other than fuel injection. It probably correspond to some metric of
;*     the totMasComp curve (average or max under given conditions). From 1G and 2G numbers,
;*     It could correspond to the max of the masComp + t_masComp(freq) curve multiplied 
;*     by 0.808*128? It could also correspond to the masComp + t_masComp(freq) curve
;*     sampled at around 69Hz and multiplied by 128.
;*     
;*          masScalar = maxTotMasComp*0.808*128 = totMasComp(69Hz)*128
;*     
;*     We then have in the case of masScalar = maxTotMasComp*0.808*128:
;*     
;*         airVol16 = numPulsePerCasInterrupts * $9c * masScalar / 65536
;*                  = numPulsePerCasInterrupts * $9c * maxTotMasComp*0.808*128 / 65536
;*                  = numPulsePerCasInterrupts * maxTotMasComp * 0.2462
;*                  = numPulsePerCasInterrupts * maxTotMasComp/2452 * 2452*0.2462
;*                  = numPulsePerCasInterrupts * maxTotMasComp/2452 * 603.68
;*     
;*     since totMasComp/2452 is litreOfAirPerAirflowSensorPulse, we have
;*     
;*         airVol16 = numPulsePerCasInterrupts * litreOfAirPerAirflowSensorPulse * 603.68
;*     
;*     Using again 1.18g/litre air density we get
;*     
;*         airVol16 = numPulsePerCasInterrupts * litreOfAirPerAirflowSensorPulse *1.18 * 603.68/1.18
;*                  = numPulsePerCasInterrupts * gramsOfAirPerAirflowSensorPulse * 512
;*                  = gramsOfAirPerCasInterrupts * 512
;*     
;*     In that case, airVol16/512 can be seen has having units of gramsOfAirPerCasInterrupts 
;*     (grams of air entering one cylinder). Note that the factor of 512 is not random, the
;*     factor 0.808 is used to get it in that case...
;*     
;*     The load index values used to interpolate the fuel map is then
;*     
;*         airVol16/2 <= 96
;*     
;*             loadIndex = (airVol16/2-32)/16 
;*                       = (gramsOfAirPerCasInterrupts*512/2 -32)/16
;*                       = gramsOfAirPerCasInterrupts*16-2
;*     
;*         airVol16/2 >= 96
;*     
;*             loadIndex = gramsOfAirPerCasInterrupts * 512/2 * 0.668/16
;*                       = gramsOfAirPerCasInterrupts*10.69
;*     
;*     Which correspond to (gramsOfAirPerCasInterrupts for each index value)
;*     
;*            0      1      2       3       4       5       6      7       8       9       10     11
;*          0.125  0.1875  0.25  0.3125  0.3750  0.4678  0.5614 0.6549  0.7485  0.8421  0.9356  1.0292
;*     
;*     gramsOfAirPerRevolution would be twice those values. Notice that the max value of 1.0292
;*     correspond to about 250HP when BSFC=0.55 which is in the range of the stock 1G 195HP...
;*     
;*     Also notice that the 8 bit airflow airVol = airVol16/2 will saturate to $ff when 
;*     airVol16/2 = 255 which correspond to gramsOfAirPerCasInterrupts = 1 gram. airVolT
;*     airVolTB and airVolB will also saturate in the same range...
;*     
;*     We can now compare these results with the stock boost gauge. It has a max range 
;*     of 1Kg per sq cm which equals 14.2 psi. The boost gauge duty cycle is given by 
;*     
;*         bGaugeODuty = t_bGauge(airVolT/32)/24
;*     
;*     When maximum airVolT = 255 = iatCompFact*airVol16/2, bGaugeODuty = 20/24 = 0.83.
;*     At 25.6 degC, iatCompFact = 1.0 and therefore airVol16=510 which translates to
;*     1g of air. boost gauge duty of 0.83 correspond to approx. 10.9psi (by eye...). 
;*     Assuming a displacement of 0.5litre per cylinder and charge air density of  1.18 
;*     (25degC, probably too low for that psi range, unless you have a perfect intercooler..) 
;*     we would get 1.18*0.5*(10.9+14.5)/14.5 = 1.03g of air per cylinder (cas 
;*     interrupt). This is quite close to the 1.0g we had earlier.
;*     
;*     The 0psi point on the gauge correspond to a duty cycle of about 40.5% which 
;*     correspond to bGaugeODuty=9.75/24 which from t_bGauge correspond to 
;*     airVolT/32=2.875 which means airVolT = 92. with iatCompFact = 1.0 @25degC, 
;*     we get airVol16 = 2*airVolT/iatCompFact = 184 which correspond to 0.36grams of air 
;*     Assuming a displacement of 0.5litre per cylinder and charge air density of 1.18@25degC
;*     we would get 1.18*0.5 = 0.59g of air per cylinder (cas interrupt) at 0psi. Compared to 
;*     0.36g we had earlier this is a large error but then there are several factor not taken onto 
;*     account in the calculations, I suppose???.
;*     
;*     
;* Engine coolant and intake air temperature 
;* ------------------------------------------
;*
;*     Approximate sensor curves (temperature 
;*     against ADC value, taken from MMCD). The
;*     control points in the service manual are
;*     quite close (0 to 2 degC off).
;*
;*
;*       ADC   ECT   IAT          ADC  ECT   IAT         ADC  ECT   IAT        ADC   ECT    IAT 
;*               degC                    degC                    degC                   degC
;*                                   
;*       $00  158.0  184.0        $40  52.0  56.0        $80  21.0  23.0       $c0   -7.0   -7.0  
;*       $01  154.4  178.1        $41  51.3  55.3        $81  20.6  22.5       $c1   -7.5   -7.6  
;*       $02  150.9  172.5        $42  50.7  54.6        $82  20.2  22.1       $c2   -8.1   -8.2  
;*       $03  147.5  167.2        $43  50.1  53.9        $83  19.8  21.7       $c3   -8.6   -8.8  
;*       $04  144.2  162.0        $44  49.5  53.3        $84  19.4  21.2       $c4   -9.2   -9.4  
;*       $05  140.9  157.1        $45  48.9  52.6        $85  19.0  20.8       $c5   -9.8  -10.1  
;*       $06  137.7  152.4        $46  48.3  52.0        $86  18.7  20.4       $c6  -10.4  -10.7  
;*       $07  134.6  148.0        $47  47.7  51.3        $87  18.3  19.9       $c7  -10.9  -11.3  
;*       $08  131.6  143.7        $48  47.2  50.7        $88  17.9  19.5       $c8  -11.5  -12.0  
;*       $09  128.6  139.6        $49  46.6  50.1        $89  17.6  19.0       $c9  -12.1  -12.6  
;*       $0a  125.7  135.7        $4a  46.1  49.4        $8a  17.2  18.6       $ca  -12.7  -13.2  
;*       $0b  122.9  132.0        $4b  45.6  48.8        $8b  16.9  18.2       $cb  -13.2  -13.9  
;*       $0c  120.2  128.5        $4c  45.0  48.2        $8c  16.5  17.7       $cc  -13.8  -14.5  
;*       $0d  117.5  125.1        $4d  44.5  47.7        $8d  16.1  17.3       $cd  -14.3  -15.1  
;*       $0e  114.9  121.9        $4e  44.0  47.1        $8e  15.7  16.8       $ce  -14.9  -15.7  
;*       $0f  112.4  118.8        $4f  43.5  46.5        $8f  15.3  16.4       $cf  -15.4  -16.3  
;*       $10  110.0  116.0        $50  43.0  46.0        $90  15.0  16.0       $d0  -16.0  -17.0  
;*       $11  107.6  113.2        $51  42.4  45.4        $91  14.5  15.5       $d1  -16.5  -17.6  
;*       $12  105.3  110.6        $52  41.9  44.9        $92  14.1  15.1       $d2  -17.0  -18.2  
;*       $13  103.0  108.1        $53  41.4  44.3        $93  13.7  14.6       $d3  -17.5  -18.8  
;*       $14  100.8  105.8        $54  40.9  43.8        $94  13.3  14.2       $d4  -18.0  -19.4  
;*       $15   98.7  103.5        $55  40.4  43.3        $95  12.9  13.7       $d5  -18.6  -20.1  
;*       $16   96.7  101.4        $56  39.9  42.8        $96  12.4  13.3       $d6  -19.2  -20.8  
;*       $17   94.7   99.4        $57  39.3  42.3        $97  12.0  12.8       $d7  -19.8  -21.5  
;*       $18   92.8   97.5        $58  38.8  41.8        $98  11.5  12.4       $d8  -20.5  -22.3  
;*       $19   91.0   95.7        $59  38.3  41.4        $99  11.1  12.0       $d9  -21.3  -23.1  
;*       $1a   89.2   93.9        $5a  37.8  40.9        $9a  10.6  11.5       $da  -22.1  -24.0  
;*       $1b   87.5   92.3        $5b  37.3  40.4        $9b  10.2  11.1       $db  -23.0  -24.9  
;*       $1c   85.9   90.7        $5c  36.9  39.9        $9c   9.7  10.7       $dc  -24.0  -26.0  
;*       $1d   84.3   89.2        $5d  36.4  39.4        $9d   9.3  10.2       $dd  -25.0  -27.1  
;*       $1e   82.8   87.7        $5e  35.9  38.9        $9e   8.8   9.8       $de  -26.2  -28.3  
;*       $1f   81.3   86.3        $5f  35.4  38.4        $9f   8.4   9.4       $df  -27.5  -29.6  
;*       $20   80.0   85.0        $60  35.0  38.0        $a0   8.0   9.0       $e0  -29.0  -31.0  
;*       $21   78.6   83.6        $61  34.5  37.5        $a1   7.5   8.5       $e1  -30.5  -32.5  
;*       $22   77.4   82.4        $62  34.0  37.0        $a2   7.1   8.1       $e2  -32.2  -34.1  
;*       $23   76.2   81.1        $63  33.6  36.4        $a3   6.6   7.7       $e3  -33.9  -35.7  
;*       $24   75.0   79.9        $64  33.1  35.9        $a4   6.2   7.3       $e4  -35.8  -37.5  
;*       $25   73.9   78.8        $65  32.7  35.4        $a5   5.8   6.9       $e5  -37.7  -39.3  
;*       $26   72.9   77.7        $66  32.3  34.9        $a6   5.3   6.4       $e6  -39.7  -41.2  
;*       $27   71.9   76.6        $67  31.8  34.4        $a7   4.9   6.0       $e7  -41.7  -43.0  
;*       $28   70.9   75.5        $68  31.4  33.9        $a8   4.5   5.6       $e8  -43.7  -44.9  
;*       $29   69.9   74.5        $69  31.0  33.4        $a9   4.0   5.2       $e9  -45.8  -46.8  
;*       $2a   69.0   73.5        $6a  30.5  32.9        $aa   3.6   4.7       $ea  -47.8  -48.7  
;*       $2b   68.1   72.5        $6b  30.1  32.4        $ab   3.2   4.3       $eb  -49.8  -50.6  
;*       $2c   67.3   71.5        $6c  29.7  31.9        $ac   2.7   3.8       $ec  -51.8  -52.4  
;*       $2d   66.4   70.6        $6d  29.3  31.4        $ad   2.3   3.4       $ed  -53.7  -54.1  
;*       $2e   65.6   69.7        $6e  28.8  30.9        $ae   1.8   2.9       $ee  -55.5  -55.8  
;*       $2f   64.8   68.8        $6f  28.4  30.4        $af   1.4   2.4       $ef  -57.3  -57.4  
;*       $30   64.0   68.0        $70  28.0  30.0        $b0   1.0   2.0       $f0  -59.0  -59.0  
;*       $31   63.1   67.1        $71  27.5  29.5        $b1   0.5   1.5       $f1  -59.0  -59.0  
;*       $32   62.3   66.3        $72  27.1  29.0        $b2   0.0   0.9       $f2  -59.0  -59.0  
;*       $33   61.5   65.5        $73  26.6  28.6        $b3  -0.3   0.4       $f3  -59.0  -59.0  
;*       $34   60.7   64.7        $74  26.2  28.1        $b4  -0.8  -0.0       $f4  -59.0  -59.0  
;*       $35   59.9   63.9        $75  25.7  27.7        $b5  -1.3  -0.5       $f5  -59.0  -59.0  
;*       $36   59.2   63.1        $76  25.3  27.2        $b6  -1.8  -1.1       $f6  -59.0  -59.0  
;*       $37   58.4   62.3        $77  24.8  26.8        $b7  -2.3  -1.6       $f7  -59.0  -59.0  
;*       $38   57.6   61.6        $78  24.4  26.4        $b8  -2.8  -2.2       $f8  -59.0  -59.0  
;*       $39   56.9   60.9        $79  23.9  25.9        $b9  -3.3  -2.8       $f9  -59.0  -59.0  
;*       $3a   56.1   60.1        $7a  23.5  25.5        $ba  -3.8  -3.3       $fa  -59.0  -59.0  
;*       $3b   55.4   59.4        $7b  23.0  25.1        $bb  -4.3  -3.9       $fb  -59.0  -59.0  
;*       $3c   54.7   58.7        $7c  22.6  24.7        $bc  -4.8  -4.5       $fc  -59.0  -59.0  
;*       $3d   54.0   58.0        $7d  22.2  24.2        $bd  -5.3  -5.1       $fd  -59.0  -59.0  
;*       $3e   53.3   57.3        $7e  21.8  23.8        $be  -5.9  -5.7       $fe  -59.0  -59.0  
;*       $3f   52.6   56.6        $7f  21.4  23.4        $bf  -6.4  -6.3       $ff  -59.0  -59.0  
;*
;*
;*
;*     
;****************************************************************************************************

;***************************************************************
;*
;*
;* Assembler general settings
;*
;*
;*
;***************************************************************
            .msfirst                        ; Assembler endian setting, do not change
            .define   E931                  ; E931 or E932 depending on desired output
            ;.define   enableCustom          ; Define to enable custom features below, comment-out to get the original E931 or E932 binaries

#ifdef enableCustom
            ;-----------------
            ; Custom settings 
            ;-----------------
codeOffset  .equ      $0100                 ; Allows to move all the code up in the eprom to make space for new code, Original offset is 0.
            .define   ftrimMax     $b3      ; Maximum fuel trim adjustement (xx/$80)%, $b3=140%
            .define   fuelMapClip  $d0      ; Fuel map max value (will be clippped to this in code)
            .define   injComp      $31      ; Injector size compensation referenced to $80=100% for 260cc at 36psi: 390cc(4E,43psi);450(4A);510(41);550(3D);600(38);650(33);660(32);680(31);700(30);750(2C);800(2A);850(27);
            .define   idleVal      $64      ; Idle speed /8, Normal $60
            .define   idleDrVal    $57      ; Idle speed /8, Normal $53
            .define   fuelCutVal   $ff      ; Fuel cut value, Original $a0
            .define   masComp      $40      ; Mas multiplier (1G:$64, 2G:$40)
            .define   masScalar    $7a03    ; Mas scalar (1G:$5e86, 2G:$7a03)
            .define   baudRate     $02      ; BaudRate divider->00(125000baud),01(15625baud),02(1953baud),03(488baud)

            .define   custDeadTime          ; Use custom injector deadtime table
            .define   custMas               ; Use custom MAS table
            .define   custFuelMap           ; Use custom fuel map
            .define   custTimingMap         ; Use custom timing map
            .define   custOctaneMap         ; Use custom octane map
            .define   octaneReset           ; Reset octane on every start
            .define   extLoadRange          ; Extended load range for timing, fuel and octane maps...
            .define   extLoadRange2         ; Use temperature compensation for load calc when extLoadRange is enabled
            .define   batteryGauge          ; Battery gauge instead of boost gauge
            .define   masLog2X              ; Double the MAS logging range
            ;.define  noFuelCut             ; Remove fuel cut altogether
            ;.define  noRamReset            ; 
            ;.define  noClosedLoop          ; Remove closed loop mode, for testing...

#else
#ifdef E931
            ;--------------------------------------
            ; Default values for original 931 ECU
            ;--------------------------------------
codeOffset  .equ      $0000                ; 
            .define   ftrimMax     $b3     ;
            .define   fuelMapClip  $ca     ;
            .define   injComp      $4a     ; 450cc injectors used at 36psi...
            .define   idleVal      $60     ;
            .define   fuelCutVal   $a0     ; 
            .define   masComp      $64     ; 
            .define   masScalar    $5e86   ;                                              
            .define   baudRate     $02     ; 
#else
            ;--------------------------------------
            ; Default values for original 932 ECU
            ;--------------------------------------
codeOffset  .equ      $0000                ;
            .define   ftrimMax     $b0     ;
            .define   fuelMapClip  $c0     ;
            .define   injComp      $4e     ; 390cc injectors used at 43psi, the value reflects that pressure difference compared to E931
            .define   idleVal      $60     ;
            .define   idleDrVal    $53     ; 
            .define   fuelCutVal   $a0     ; 
            .define   masComp      $64     ; 
            .define   masScalar    $5e86   ;                                              
            .define   baudRate     $02     ; 
#endif
#endif



;***************************************************************
;*
;*
;* Microcontroller registers
;*
;*
;***************************************************************
p1_ddr           .EQU     $0000                  ; Port 1 data direction register. Initialized with $7E=01111110  (0=intput, 1=output)
p2_ddr           .EQU     $0001                  ; Port 2 data direction register. Initialized with $16=00010110
port1            .EQU     $0002                  ; Port 1 Data register                                             
                                                 ;    bit 0 (0x01):  in  - Unused but varies(seems to have correlation with CAS), by extrapolation, set to out for injector #5 or #6 on other ECUs?                                                 
                                                 ;    bit 1 (0x02):  out - Set to 0 to activate injector #3?                                             
                                                 ;    bit 2 (0x04):  out - Set to 0 to activate injector #2?                                            
                                                 ;    bit 3 (0x08):  out - Set to 0 to activate injector #4?                                              
                                                 ;    bit 4 (0x10):  out - Fuel pump relay
                                                 ;    bit 5 (0x20):  out - Air cond. clutch
                                                 ;    bit 6 (0x40):  out - ???, reset to 0 on init and first sub    
                                                 ;    bit 7 (0x80):  in  - Reed switch, 4 square pulse (square wave) per odometer rotation, each of the 4 complete square wave correspond to ~40cm (20cm for each rising or falling edge)
port2            .EQU     $0003                  ; Port 2 Data register
                                                 ;    bit 0 (0x01):  in  - Unused but varies (seems to have correlation with CAS), by extrapolation, set to out for injector #5 or #6 on other ECUs?                                                                                                           
                                                 ;    bit 1 (0x02):  out - Set to 0 to activate injector #1?                                                                                                             
                                                 ;    bit 2 (0x04):  out - Airflow sensor active filter reset. Set/reset depending on tps,rpm,airVol,idleSwitch??????   (in serial clock)-  Connected to serial port clock???
                                                 ;    bit 3 (0x08):  in  - Connected to serial port input (if serial RE is enabled) and test connector serial interface                                                                              
                                                 ;    bit 4 (0x10):  out - Connected to serial port output (if serial TE is enabled) and test connector serial interface, controlled directly to output heart beat code to test connector
                                                 ;    bit 5 (0x20):  in  - 0, ECU Operating mode PC0 (latched on ECU reset)                                                               
                                                 ;    bit 6 (0x40):  in  - 1, ECU Operating mode PC1                                                                                      
                                                 ;    bit 7 (0x80):  in  - 0, ECU Operating mode PC2                                                                                      
p3_ddr           .EQU     $0004                  ; Port 3 data direction register, Initialized to 0 (all input) 
p4_ddr           .EQU     $0005                  ; Port 4 data direction register, Initialized to 0 (all input) 
port3            .EQU     $0006                  ; Port 3 Data register                                         
                                                 ;    bit 0 (0x01):  in  - IG2 related, 0 when IG2 at +12V??? (ABS unit?????)  see around Md4d4 and M23db?                                    
                                                 ;    bit 1 (0x02):  in  - IG1. 0 when IG1 at +12V. Set to 1 when power has been turned off and control relay is about to turn off. i.e. ECU is going to loose power in a short while.
                                                 ;    bit 2 (0x04):  in  - Top dead center sensor signal (TDC). Set to 0 when TDC signal is active
                                                 ;    bit 3 (0x08):  in  - Set to 1 if power steering pump is activated
                                                 ;    bit 4 (0x10):  in  - Air cond. switch (1=off). 0 indicate that AC should be activated, if possible... Connected to the output of the A/C control unit through the the ECT switch (switch cuts signal therefore asking ECU to cut clutch...)
                                                 ;    bit 5 (0x20):  in  - Inhibitor switch (A/T only) Set to 1 when transmission is in park or neutral
                                                 ;    bit 6 (0x40):  in  - 0 if key is in start position
                                                 ;    bit 7 (0x80):  in  - Set to 1 when the idle switch is on
port4            .EQU     $0007                  ; Port 4 data register 
                                                 ;    bit 0 (0x01):  in  - c0, set when config resistor R129 is installed. used in conjucntion with c1 in #t_strap1 lookup, FEDERAL (0) or CALIFORNIA (1)                                                
                                                 ;    bit 1 (0x02):  in  - c1, set when config resistor R130 is installed. used in conjucntion with c0 in #t_strap1 lookup, FWD (0) or AWD (1)                                                
                                                 ;    bit 2 (0x04):  in  - Signal from the ignition sensing circuit. Toggled on every ignition signal sent to the coil (toggled on every cylinder ignition if the power transistor output changed...), stays at the given level from one ignition to the other
                                                 ;    bit 3 (0x08):  in  - Set to 1 when ECU test mode terminal is grounded                
                                                 ;    bit 4 (0x10):  in  - Set to 1 when the timing terminal is grounded                                                 
                                                 ;    bit 5 (0x20):  in  - Knock sensor feedback? (set to 1 indicates it works...)???                                                
                                                 ;    bit 6 (0x40):  in  - Fuel pump driven feedback? 0 when FP is driven?                                               
                                                 ;    bit 7 (0x80):  in  - Injector driven feedback. Set to 0 when injector circuit is working properly??? Bit is tested when an injector to test was just deactivated and no other injector is active??? Bit might be loaded on the falling edge of the injector driving current???
                                                 ;                         Service manual says injector is bad if injector is not continuously driven for 4 sec during idle or cranking. 4 sec is implemented by fault code regular code... So this bit would be "injector driven" bit
t1_csr           .EQU     $0008                  ; Dual of $18, Timer1 control and status register, dual of t2_csr                                                             
                                                 ;    bit 0 (0x01): Injector 1 activation/deactivation bit. Bit is transfered to port2.1 when a t1 or t2 output compare interrupt is generated???
                                                 ;    bit 1 (0x02): cas edge detection polarity, set to 0 to trigger an interrupt on the CAS rising edge, set to 1 to trigger an interrupt on the CAS falling edge
                                                 ;    bit 2 (0x04): By extrapolation, set to 0 when injector 5/6 is on????
                                                 ;    bit 3 (0x08): Set to 1 to enable outCompInt1 interrupts (injector 1 only or 1 and 4)?
                                                 ;    bit 4 (0x10): Set to 1 to enable inCaptInt1 interrupts (cas)?
                                                 ;    bit 5 (0x20): By extrapolation, set to 0 when injector 5/6 is on????
                                                 ;    bit 6 (0x40): 1 indicate that outCompInt1 interrupt is pending/has been activated (injector #1 or #4 activation/deactivation)                                                                                               
                                                 ;    bit 7 (0x80): 1 indicate that inCaptInt1 interrupt is pending/has been activated (cas)
t1t2_clk         .EQU     $0009   ;:$000a        ; Free running counter at 1MHz for t1 and t2 timer functions
t1_outCmpWr      .EQU     $000b   ;:$000c        ; Dual of $001B, Output compare register, value is compared to t1t2_clk and when a match occurs, injector ports are loaded with the values indicated in t1_csr. Seems 2 or 3 successive value can be written (injector activation and deactivation times...)
t1_inCapt        .EQU     $000d   ;:$000e        ; Cas sensor input capture register. Contains the value of t1t2_clk when the cas sensor "edge" was detected
L000f            .EQU     $000f                  ; Init to 0??????????????
sci_baud         .EQU     $0010                  ; Serial communication rate and mode control register (clock source = 2MHz)                     
                                                 ;    bit 0 (0x01): SS0, [SS1:SS0] is baud rate divider, 00(16) 01(128) 10(1024) 11(4096), assuming basic clock of 2MHZ, we get 125000baud, 15625baud, 1953baud, 488baud                           
                                                 ;    bit 1 (0x02): SS1                            
                                                 ;    bit 2 (0x04): CC0, [CC1:CC0] is the mode control register                          
                                                 ;    bit 3 (0x08): CC1                            
                                                 ;    bit 4 (0x10): NU?                                                                
                                                 ;    bit 5 (0x20): NU?                                                                
                                                 ;    bit 6 (0x40): NU?                                                                
                                                 ;    bit 7 (0x80): NU?                                                                
sci_scr          .EQU     $0011                  ; Serial communication status and control register?                             
                                                 ;    bit 0 (0x01): WU   - Wake-up on idle line                                     
                                                 ;    bit 1 (0x02): TE   - transmit enable, set to 1                                
                                                 ;    bit 2 (0x04): TIE  - Tx interrupt enable, reset to 0                          
                                                 ;    bit 3 (0x08): RE   - Rx enable, checked for set before tx                     
                                                 ;    bit 4 (0x10): RIE  - Rx interrupt enable,  Reset/set to 0/1 in real time int        
                                                 ;    bit 5 (0x20): TDRE - transmit data register empty                             
                                                 ;    bit 6 (0x40)  ORFE - Overrun and framing error                                
                                                 ;    bit 7 (0x80): RDRF - Read data register full                                  
sci_rx           .EQU     $0012                  ; SCI data read register   
sci_tx           .EQU     $0013                  ; SCI data write register  
ramControl       .EQU     $0014                  ; RAM control register/battery saving status register
                                                 ;    bit 0 (0x01): Init to 0? 
                                                 ;    bit 1 (0x02): Init to 0?
                                                 ;    bit 2 (0x04): Init to 0?
                                                 ;    bit 3 (0x08): Init to 0?
                                                 ;    bit 4 (0x10): Init to 0?
                                                 ;    bit 5 (0x20): Init to 0?
                                                 ;    bit 6 (0x40): Ram enable bit??? Set to 1 after the fresh reset initialization is done, reset to 0 in failureInt?
                                                 ;    bit 7 (0x80): Power standby bit, Set to 1 after the fresh reset initialization is done, reset to 0 if we loose standby power (i.e. 0 when ram content was not preserved after a power-off) 
p5_ddr           .EQU     $0015                  ; Port 5 data direction register, Initialized to $#fe (1111 1110)
port5            .EQU     $0016                  ; Port 5      
                                                 ;    bit 0 (0x01): in  - CAS, crank angle sensor signal. Set to 0 when the CAS signal is activated                                                                                  
                                                 ;    bit 1 (0x02): out - Power transistor output for cyl 1 and 4. Set to 0 to energize the coil. 
                                                 ;    bit 2 (0x04): out - Power transistor output for cyl 2 and 3. Set to 0 to energize the coil. 
                                                 ;    bit 3 (0x08): out - EGR control solenoid output
                                                 ;    bit 4 (0x10): out - Fuel pressure solenoid output (0=activated)                                                                                
                                                 ;    bit 5 (0x20): out - Boost control solenoid output
                                                 ;    bit 6 (0x40): out - ISC step control, see table t_iscPattern                                                                 
                                                 ;    bit 7 (0x80): out - ISC step control, see table t_iscPattern                                                                 
L0017            .EQU     $0017                  ; Init to 0?????
t2_csr           .EQU     $0018                  ; Timer2 control and status register, uses the same clock as timer 1 (t1t2_clk)
                                                 ;    bit 0 (0x01): Injector 3 activation/deactivation bit. Bit is transfered to port1.1 when a t1 or t2 output compare interrupt is generated
                                                 ;    bit 1 (0x02): Airflow sensor edge detection polarity (0=rising edge, 1=falling edge, or the opposite?). See masProc subroutine header
                                                 ;    bit 2 (0x04): Injector 2 activation/deactivation bit. Bit is transfered to port1.2 when a t1 or t2 output compare interrupt is generated
                                                 ;    bit 3 (0x08): Set to 1 to enable outCompInt2 interrupts (injectors 2, 3 and maybe 4)?
                                                 ;    bit 4 (0x10): Set to 1 to enable inCaptInt2 interrupts (airflow sensor)?
                                                 ;    bit 5 (0x20): Injector 4 activation/deactivation bit. Bit is transfered to port1.3 when a t1 or t2 output compare interrupt is generated
                                                 ;    bit 6 (0x40): 1 indicate that outCompInt2 interrupt is pending/has been activated (injectors #2 or #3 activation/deactivation)                                                                                               
                                                 ;    bit 7 (0x80): 1 indicate that inCaptInt2 interruot is pending/has been activated (airflow sensor pulse)  
t3_csr0          .EQU     $0019                  ; Normally the dual of $0009 but since the ECU didn't need the equivalent of t1t2_clk for timer 2 (timer 1 and timer 2 both use t1t2_clk), it is used for something else...
                                                 ; timer 3 (coil) control ans status register 0 ???
                                                 ;    bit 0 (0x01): 0 all the time except, set to 1 when no cas interrupt received for 1.275sec???
                                                 ;    bit 1 (0x02): 1 on every loop
                                                 ;    bit 2 (0x04): 1 Set to 0 when the output compare interrupt need to energize coil for cylinder 1 or 4, i.e. bit will be loaded in port5.1 when interrupt occur
                                                 ;    bit 3 (0x08): 1 Set to 0 when the output compare interrupt need to energize coil for cylinder 2 or 3, i.e. bit will be loaded in port5.2 when interrupt occur
                                                 ;    bit 4 (0x10): 1 on init but not on every loop, Used to decide which of t3_clock1 or t3_clock2 should be used upon a CAS interrupt???
                                                 ;    bit 5 (0x20): 0 on every loop
                                                 ;    bit 6 (0x40): 1 on every loop
                                                 ;    bit 7 (0x80): 0 on every loop
t3_csr1          .EQU     $001a                  ; Normally the dual of $000a but since the ECU didn't need the equivalent of t1t2_clk for timer 2 (timer 1 and timer 2 both use t1t2_clk), it is used for something else...
                                                 ; timer 3 (coil) control ans status register 1???
                                                 ;    bit 0 (0x01): 0 Cylinder 1/4 or 2/3 ?? output compare detection polarity?
                                                 ;    bit 1 (0x02): 1 Cylinder 1/4 or 2/3 ?? output compare detection polarity?
                                                 ;    bit 2 (0x04): 0 Cylinder 1/4 or 2/3 ?? output compare detection polarity?
                                                 ;    bit 3 (0x08): 1 Cylinder 1/4 or 2/3 ?? output compare detection polarity?
                                                 ;    bit 4 (0x10): 0
                                                 ;    bit 5 (0x20): 0
                                                 ;    bit 6 (0x40): 0 1 indicate that the outCompInt3 interrupt is pending/has been activated???                                                                                               
                                                 ;    bit 7 (0x80): 0
t2_outCmpWr      .EQU     $001b   ;:$001c        ; Dual of $0b:$0c, Output compare register, value is compared to t1t2_clk and when a match occurs, injector ports are loaded with the values indicated in t2_csr. seems 2 or 3 successive value can be written (injector activation and deactivation times...)
t2_inCapt        .EQU     $001d   ;:$001e        ; Dual of $0d:$0e, Airflow sensor input capture register. Contains the value of t1t2_clk when an airflow sensor pulse edge detected
adc_ctl          .EQU     $001f                  ; ADC control; [bit 3 = start bit?, bit 2:0 = channel select ]???
                                                 ;    bit 0 (0x01): c0 [c2:c1:c0] is the port number to use aas input to the A/D converter                                                                      
                                                 ;    bit 1 (0x02): c1                                                                       
                                                 ;    bit 2 (0x04): c2                                                                       
                                                 ;    bit 3 (0x08): Start bit, set to 1 to start A/D conversion                                                                         
                                                 ;    bit 4 (0x10): ?                                                                       
                                                 ;    bit 5 (0x20): ?                                                                       
                                                 ;    bit 6 (0x40): ?
                                                 ;    bit 7 (0x80): ?                                                                       
adc_data         .EQU     $0020                  ; 8 bit A to D converter result data
L0021            .EQU     $0021                  ; Unused?
L0022            .EQU     $0022                  ; Unused?
L0023            .EQU     $0023                  ; Unused?
L0024            .EQU     $0024                  ; Init to 0?
L0025            .EQU     $0025                  ; Unused?
rti_ctl          .EQU     $0026                  ; Timer control and status register for real time interrupt? init to $4D = 0100 1101
                                                 ;    bit 0 (0x01): ?                                                                       
                                                 ;    bit 1 (0x02): ?                                                                       
                                                 ;    bit 2 (0x04): ?                                                                       
                                                 ;    bit 3 (0x08): ?                                                                       
                                                 ;    bit 4 (0x10): ?                                                                       
                                                 ;    bit 5 (0x20): ?                                                                       
                                                 ;    bit 6 (0x40): Set to 1 to enable rti interrupts?
                                                 ;    bit 7 (0x80): ?                                                                       
rti_freq         .EQU     $0027                  ; Real time interrupt frequency setting: Freq = 125000/(256-x) where x is the content of rti_freq
L0028            .EQU     $0028                  ; Unused?
t3_clock1        .EQU     $0029   ;:$002a        ; Readable counter. Frequency seems to be 250KHz (2MHz/8).
t3_outCmpWr      .EQU     $002b   ;:$002c        ; Writable output compare register for counters at $0029:$002A and $002D:$002E
                                                 ; Seems to be double buffered...
t3_clock2        .EQU     $002d   ;:$002e        ; Dual of $0029. I think it always has the same value as t3_clock1 but ipon a cas interrupt, the code decides between t3_clock1 and t3_clock2???
port6            .EQU     $002f                  ; Port 6 (all output, no data direction register?)                                             
                                                 ;    bit 0 (0x01): out - Write 1 to reset instant knock count???
                                                 ;    bit 1 (0x02): out - ??? Set to 0 when rpm>4688rpm, set to 1 when rpm<4600, could be some kind of ECU board filter setting for the knock sensor???
                                                 ;    bit 2 (0x04): out - Boost gauge output
                                                 ;    bit 3 (0x08): out - Check engine (CE) light
                                                 ;    bit 4 (0x10): out - Reset to 0 to activate purge solenoid?
                                                 ;    bit 5 (0x20): out - Toggled at F924 if main loop frequency >20Hz, could be tied to ECU reset in case of trouble (COP clock)
                                                 ;    bit 6 (0x40): out - Not used?                                                         
                                                 ;    bit 7 (0x80): out - Not used?                                                         
                 
                 ;------------------------------
                 ; Block of 16 probably unused 
                 ; microcontroller registers??? 
                 ;------------------------------
L0030            .EQU     $0030                  ; Unused
L0031            .EQU     $0031                  ; Unused
L0032            .EQU     $0032                  ; Unused
L0033            .EQU     $0033                  ; Unused
L0034            .EQU     $0034                  ; Unused
L0035            .EQU     $0035                  ; Unused
L0036            .EQU     $0036                  ; Unused
L0037            .EQU     $0037                  ; Unused
L0038            .EQU     $0038                  ; Unused
L0039            .EQU     $0039                  ; Unused
L003a            .EQU     $003a                  ; Unused
L003b            .EQU     $003b                  ; Unused
L003c            .EQU     $003c                  ; Unused
L003d            .EQU     $003d                  ; Unused
L003e            .EQU     $003e                  ; Unused
L003f            .EQU     $003f                  ; Unused 
            


;***************************************************************
;*
;*
;* Block of RAM used to preserve settings when the ECU is off 
;* (This block is not cleared to 0 when the ECU is powered-on)
;*
;*
;***************************************************************
ftrim_low        .EQU     $0040                  ; Fuel trim low  (.78x)%                     
ftrim_mid        .EQU     $0041                  ; Fuel trim mid  (.78x)%                     
ftrim_hi         .EQU     $0042                  ; Fuel trim high (.78x)%                     
ftrimCntr        .EQU     $0043                  ; Fuel trim counter. This counter is increased/decreased by 5 (+/-5 at 40Hz) whenever a fuel trim is below/above o2Fbk threshold. The fuel trim is increased/decreased by 1 whenever this counter rools over, giving an effective update rate of 40Hz/(256/5)=0.78125Hz for the fuel trims update                                           
isc0             .EQU     $0044   ;:$0045        ; iscm (isc0 or isc1) are 16 bit long term correction factors/feedback for the isc step adjustment. It is centered at $8000 (100%, no correction). Init to $8c00, A value higher than $8000 indicate that we need to increase the isc step since the current rpm is lower than the desired one
                                                 ; The isc step used is increased/decreased by iscm/256 - $80. iscm is updated from the short term iscYn variable.The isc step used is increased/decreased by iscm/256 - $80
                                                 ; isc0 is the long term learning variable when A/C is off, 16 bits, see iscPointers function
isc1             .EQU     $0046   ;:$0047        ; isc1 is the long term learning variable when A/C is on, 16 bits, see iscPointers function
iscStepCom       .EQU     $0048                  ; isc step complement, shlould be equal to  ~iscStepCurr & $7f. Not sure of its utility???
iscStepCurr      .EQU     $0049                  ; Current isc step (x) range of 0 to 120 (or 13x???)                             
iscPatrnIdx      .EQU     $004a                  ; Current ISC pattern index, two lower bits are used as index into t_iscPattern to update port5.6.7 in order to move the ISC spindle...                                          
iscFlags0        .EQU     $004b                  ; Flag register for ISC updating
                                                 ;    bit 0 (0x01): Set to 1 once the isc calibration is started. This means we initialized iscStepCurr to 135 and set the iscStepTarg to 0. The spindle will therefore be moved to the minimum position irrespective of the starting position, which will allow us to know its real position... Reset to 0 once calibration is finished and ISC is back to iscStepCurr=6
                                                 ;    bit 1 (0x02): Set to 1 once the isc calibration is finished. i.e. once iscStepCurr reached 0. See bit 0.  Reset to 0 once calibration is finished and ISC is back to iscStepCurr=6
                                                 ;    bit 2 (0x04): Set when basic idle speed adjustment mode is active 
                                                 ;    bit 3 (0x08): Set to 1 when a fixed isc step is used because the engine is running but we are not receiving airflow sensor interrupts. 
                                                 ;    bit 4 (0x10): Set to 1 when a fixed isc step is used because the ECU is about to loose power 
                                                 ;    bit 5 (0x20): Set to 1 when ISC min calibration need to be performed, i.e. move the spindle 135 steps toward 0, that ensures the spindle is positionned at the minimum position, wherever we started from... Reset to 0 once calibration is finished and ISC is back to iscStepCurr=6
                                                 ;    bit 6 (0x40): Set to 1 when the ISC max calibration has been performed, see bit 7
                                                 ;    bit 7 (0x80): Set to 1 when ISC max calibration need to be performed. Max calibration is achieved by setting iscStepTarg to 135, wait for iscStepCurr to reach 135 (higher than max usable valu of 120) and then set iscStepCurr to 120 since this is the max usable value 
stFaultHi        .EQU     $004c                  ; Stored faults, High byte. Notice we say its high byte because it is the ECU convention to store high byte before low byte and it is also used that way in the code                   
stFaultLo        .EQU     $004d                  ; Stored faults, Low byte. 
faultHi          .EQU     $004e                  ; Faults, high byte. Notice we say its high byte because it is the ECU convention to store high byte before low byte and it is also used that way in the code                   
faultLo          .EQU     $004f                  ; Faults, low byte                         
o2BadCnt         .EQU     $0050                  ; Used to test the o2 sensor, 0 when 02 sensor not in fault or not tested, 1 or greater when o2 sensor is bad. Can only increase by 1 each time the ECU is turned on and sensor is tested
egrtBadCnt       .EQU     $0051                  ; Used to test the egrt sensor, 0 when egrt sensor not in fault or not tested, 1 or greater when egrt sensor is bad. Can only increase by 1 each time the ECU is turned on and sensor is tested
octane           .EQU     $0052                  ; Octane value used in timing advance calculation with min 0(bad fuel...), max 255 (no knock). Updated at 2.5Hz from knockSum under specific circumstances (decremented by 1 if knocksum>5, incremented by 1 if knocksum<3)
knockFlags       .EQU     $0053                  ; Flags related to knock sensor
                                                 ;    bit 0 (0x01): 
                                                 ;    bit 1 (0x02): 
                                                 ;    bit 2 (0x04): 
                                                 ;    bit 3 (0x08): 
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): 
                                                 ;    bit 6 (0x40): Set to 1 when engine has been runnning for more than 1 sec
                                                 ;    bit 7 (0x80): Set to 1 when airVol>$49, used to know whether engine is under high or loaw load for knockSum and knockSum decay calculations
L0054            .EQU     $0054                  ; UNUSED?
config1          .EQU     $0055                  ; Configuration flags depending on config resistors, Loaded with t_strap1[port4& (#$03 << 1)]
                                                 ;    bit 0 (0x01): 
                                                 ;    bit 1 (0x02): 
                                                 ;    bit 2 (0x04): 
                                                 ;    bit 3 (0x08): 
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): 
                                                 ;    bit 6 (0x40): 
                                                 ;    bit 7 (0x80): 
config2          .EQU     $0056                  ; Configuration flags depending on config resistors, Loaded with t_strap1[port4& (#$03 << 1)+1]  
                                                 ;    bit 0 (0x01): 
                                                 ;    bit 1 (0x02): 
                                                 ;    bit 2 (0x04): 
                                                 ;    bit 3 (0x08): 
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): 
                                                 ;    bit 6 (0x40): 
                                                 ;    bit 7 (0x80): 
                                                          
                                                                                            
                                                                                           
;***************************************************************
;*
;*
;* RAM, cleared to 0 when the ECU is powered-on
;*
;*
;***************************************************************
ramClearStart    .EQU     $0057
temp1            .EQU     $0057                  ;
temp2            .EQU     $0058                  ;
temp3            .EQU     $0059                  ;
temp4            .EQU     $005a                  ;
temp5            .EQU     $005b                  ;
temp6            .EQU     $005c                  ;
temp7            .EQU     $005d                  ;
temp8            .EQU     $005e                  ;
temp9            .EQU     $005f                  ;
L0060            .EQU     $0060                  ; Unused
casFlags0        .EQU     $0061                  ; Flag register
                                                 ;    bit 0 (0x01): Bit is set to 1 when rpm(Tcas) >= 505, reset when rpm(Tcas) < 401 (hysteresis)
                                                 ;    bit 1 (0x02): Old value of bit 0 
                                                 ;    bit 2 (0x04): 1 if rpm(Tcas) >  1775rpm
                                                 ;    bit 3 (0x08): Old value of bit 2 
                                                 ;    bit 4 (0x10): 1 if rpm(Tcas) >  1540rpm 
                                                 ;    bit 5 (0x20): 1 if rpm(Tcas) >  4801rpm
                                                 ;    bit 6 (0x40): Set to 1 if timing adjustment mode is active
                                                 ;    bit 7 (0x80): Unused?
ignFallFlags     .EQU     $0062                  ; Coil ignition scheduling on the cas falling edge
                                                 ;    bit 0 (0x01): Set to 1 when coil ignition was not scheduled on the CAS 
                                                 ;                  rising edge and therefore need to be scheduled on the CAS falling edge?
                                                 ;    bit 1 (0x02): not used
                                                 ;    bit 2 (0x04): not used 
                                                 ;    bit 3 (0x08): not used
                                                 ;    bit 4 (0x10): not used
                                                 ;    bit 5 (0x20): not used
                                                 ;    bit 6 (0x40): not used
                                                 ;    bit 7 (0x80): not used
enerFlags        .EQU     $0063                  ; Coil energization state, bit 0 and 1 are mutually exclusive, they are never set at the same time...
                                                 ; Note that when rpm is low, these flags might not be set as indicated (during cranking?)
                                                 ;    bit 0 (0x01): Set to 1 when coil is currently energized?
                                                 ;    bit 1 (0x02): Set to 1 when coil energization has been scheduled?
                                                 ;    bit 2 (0x04): not used
                                                 ;    bit 3 (0x08): not used
                                                 ;    bit 4 (0x10): not used
                                                 ;    bit 5 (0x20): not used
                                                 ;    bit 6 (0x40): not used
                                                 ;    bit 7 (0x80): not used
TcasLast0        .EQU     $0064                  ; TcasLast0:TcasLast1 (250KHz clock) is identical to TcasNew0:TcasNew1 but it has been validated for range. Basically it is the last Tcas value that was valid
TcasLast1        .EQU     $0065                  ; See TcasLast0 
TcasNew0         .EQU     $0066                  ; TcasNew0:TcasNew1 (250KHz clock) is the new value of Tcas calculated during the CAS interrupt 
TcasNew1         .EQU     $0067                  ; See TcasNew0
casRiseTime0     .EQU     $0068                  ; casRiseTime0:casRiseTime1 (250KHz clock) is the clock value when the last CAS rising edge interrupt occured  
casRiseTime1     .EQU     $0069                  ; See casRiseTime0
casFallTime0     .EQU     $006a                  ; casFallTime0:casFallTime1 (250KHz clock) is the clock value when the last CAS falling edge interrupt occured  
casFallTime1     .EQU     $006b                  ; See casFallTime0
timCas0          .EQU     $006c                  ; The current ignition timing (xx/256*90)degrees referenced to the CAS pulse rising edge (75deg BTDC), [timCas0:timCas1] =  256 * (75.77 - degAdv)/90, calculated from tim61 + $002a
timCas1          .EQU     $006d                  ; See timCas0
ignRelTime0      .EQU     $006e                  ; [ignRelTime0:ignRelTime1] is the current ignition time minus 72us measured in 1/250000 sec (timer clock) and referenced to the CAS rising edge (75deg BTDC). Calculated from timCas0: [ignRelTime0:ignRelTime1] = [TcasNew0:TcasNew1]/2 * [timCas0:timCas1]/256 - $0012
ignRelTime1      .EQU     $006f                  ; See ignRelTime0
ignFallRelTime0  .EQU     $0070                  ; Similar to ignRelTime0 but measured from te cas falling edge, used to schedule ignition when the timing is high (past the cas falling edge...)
ignFallRelTime1  .EQU     $0071                  ; See ignFallRelTime0
enerLenX0        .EQU     $0072                  ; One of the coil energization durations, the one used depends on current conditions...  
enerLenX1        .EQU     $0073                  ; See enerLenX0
enerAbsTime0     .EQU     $0074                  ; Coil energization absolute time (t3_clock1)
enerAbsTime1     .EQU     $0075                  ; See enerAbsTime0
ignTime0         .EQU     $0076                  ; Coil ignition absolute time (t3_clock1)
ignTime1         .EQU     $0077                  ; See ignTime1
enerAbsTimeNext0 .EQU     $0078                  ; Coil absolute energization time (ignTime1) but only used when energization of the "next cylinder" is scheduled from the preceeding cylinder coil ignition time...
enerAbsTimeNext1 .EQU     $0079                  ; See enerAbsTimeNext0
TcasLast128      .EQU     $007a                  ; Set to TcasLast0/128
tdcMask0         .EQU     $007b                  ; tdcMask0:tdcMask1 contains $0204 when TDC signal is active (cylinder 1 or 4) on the CAS rising edge, $0402 otherwise. Toggled on every CAS rising edge
tdcMask1         .EQU     $007c                  ; See tdcMask0
tim61            .EQU     $007d                  ; Current timing (xx/256*90)degrees referenced to 61deg BTDC, tim61 = 256 * (61 - degAdv) / 90, where degAdv is the timing advance in degrees. Calculated from tim61Tot0
temp20           .EQU     $007e                  ; 
temp21           .EQU     $007f                  ;
temp22           .EQU     $0080                  ;
temp23           .EQU     $0081                  ;
temp24           .EQU     $0082                  ;
tdcCasCount      .EQU     $0083                  ; CAS rising edge counter when key is not in start, incremented on every CAS rising edge up to a maximum value of 6, used in TDC synch. operation
T40s_casInt      .EQU     $0084                  ; Initialized to 1.275sec on every CAS rising edge interrupt and decremented in first subroutine at ~40Hz. Will reach 0 (expire) only when no CAS interrupt was received for over 1.275sec, i.e. engine is really not rotating or something is wrong?
coilChkFlags     .EQU     $0085                  ; Flag register used to validate the ignition signal using the ignition coil sensing circuit
                                                 ;    bit 0 (0x01): Injector 1, set to 1 to indicate that the injector can be used, 0 indicate injector is disabled because ignition is not happening on the corresponding cylinder
                                                 ;    bit 1 (0x02): Injector 3, set to 1 to indicate that the injector can be used, 0 indicate injector is disabled because ignition is not happening on the corresponding cylinder
                                                 ;    bit 2 (0x04): Injector 4, set to 1 to indicate that the injector can be used, 0 indicate injector is disabled because ignition is not happening on the corresponding cylinder
                                                 ;    bit 3 (0x08): Injector 2, set to 1 to indicate that the injector can be used, 0 indicate injector is disabled because ignition is not happening on the corresponding cylinder
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): Set to 1 when engine is running and rpm<5000 and 8V<=battRaw<=18V, meaning we can proceed with checking the ignition
                                                 ;    bit 6 (0x40): 
                                                 ;    bit 7 (0x80): Set to 1 when we detected that several ignition signals were missing, ignition is not working properly.
p4Latched        .EQU     $0086                  ; Loaded with port4 and checked for bit #$04 in CAS interrupt
timAdjFlags      .EQU     $0087                  ; Timing adjustment mode flags
                                                 ;    bit 0 (0x01): Set when rpm31>2000rpm, reset when rpm31 goes lower than 1813rpm (hysteresis) 
                                                 ;    bit 1 (0x02): 
                                                 ;    bit 2 (0x04): 
                                                 ;    bit 3 (0x08): 
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): 
                                                 ;    bit 6 (0x40):
                                                 ;    bit 7 (0x80): Set to 1 when timing adjustment mode is active (timing terminal is grounded but the ECU test mode terminal is not grounded
tim61Tot0        .EQU     $0088                  ; New target timing (xx/256*90)degrees referenced to 61deg BTDC. knockSum is added to this value in order to retard timing further and then a maximum rate of change of 22.5deg/iteration is applied. The result becomes the new timing to apply (tim61 and timCas0:timCas1). Calculated from advTotal
enerLen          .EQU     $0089                  ; Coil energization time as loaded from the t_enerLen(battRaw) table. Actual energization time used might be different, longer...
timingAdv        .EQU     $008a                  ; Current timing advance, (x-10)degrees, timingAdv = degAdv+10, Calculated from tim61
knockSum         .EQU     $008b                  ; Current knock sum value
T200s_knock      .EQU     $008c                  ; Knock attenuation timer decremented at 200Hz and looping at 1.67Hz or 100Hz depending on airVol, knockSum is decremented by 1 every time this timer expires 
airCnt0          .EQU     $008d                  ; [airCnt0:airCnt1:airCnt2] is the exponentially averaged 24 bit air count (input is 16 bit [airCntNew0:airCntNew1]*256)
airCnt1          .EQU     $008e                  ; See airCnt0
airCnt2          .EQU     $008f                  ; See airCnt0
airCntNew0       .EQU     $0090                  ; airCntNew0:airCntNew1 is the 16 bits air count used as input to [airCnt0:airCnt1:airCnt2]. It is equal (N+r) * $9c where N is the number of airflow sensor pulse counted by the mas interrupt between each cas interrupt (1 cas interrupt for every cylinder cycle, 4 per every 2 engine rotations) r<=1 is a "remainder" proportional to the time elapsed since the last interrupt... 
airCntNew1       .EQU     $0091                  ; See airCntNew0
oldAirCnt0       .EQU     $0092   ;:$0093        ; This is the old value of airCnt0:airCnt1 used to compute some kind of air count derivative
airDiffPos       .EQU     $0094                  ; Contains airCnt0-oldAirCnt0 when the difference is positive, This is kind of the derivative of air count which is positive when air count is increasing (acceleration)
airDiffNeg       .EQU     $0095                  ; Contains abs(airCnt0-oldAirCnt0) when the difference is negative (contains oldAirCnt0-airCnt0...). This is kind of the derivative of air count which is negative when air count is decreasing (decceleration)
t1_lastCas       .EQU     $0096   ;:$0097        ; Latest value of t1_inCapt when CAS interrupt was called
t2_lastMas       .EQU     $0098   ;:$0099        ; Latest value of t2_inCapt when MAS interrupt was called                                                                             
t2_diff8         .EQU     $009a   ;:$009b        ; Time between 2 edges (2 edges per pulse...) of the airflow sensor with timer based rounding (see code), calculated on each mas interrupts from t2_inCapt/8
airQuantum       .EQU     $009c                  ; This value ($9c) is the the "amount of air" corresponding to 1 airflow sensor pulse. Using a non unitary value allows the ECU to interpolate the airflow between pulses, i.e. if at the time we calculate airflow we are at 2/3 in between two pulses then we add 2/3 of airQuantum...  
                                                 ; It is added to [airCntNew0:airCntNew1] on each mas interrupt call (accumulates N times $9C...).  A ratio is also applied to this value when it is added to [airCntNew0:airCntNew1] for the last time (partial count in between pulses) before airCnt0 is calculated.
L009d            .EQU     $009d                  ; Not used?
masCasFlags      .EQU     $009e                  ; Flag register
                                                 ;    bit 0 (0x01): Bit is set when the CAS rising edge interrupt code is executed to flag the event to the main loop. Flag is read from main loop to update rpmX4Filt and then reset
                                                 ;    bit 1 (0x02): 
                                                 ;    bit 2 (0x04): 
                                                 ;    bit 3 (0x08): 
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): 
                                                 ;    bit 6 (0x40):
                                                 ;    bit 7 (0x80): Scaling for the airflow sensor pulse counting. Set to 0 when we count both the rising and falling edge of the airflow sensor pulse. Set to 0 in case we count only the rising edges (or only the falling ones)
airFiltFact      .EQU     $009f                  ; airCnt0 exponential averaging factor with alpha = airFiltFact/256, 0<=alpha<=1, basically used to filter the air count: new airCnt0 = alpha * old airCnt0 + (1-alpha)*newAirCntValue, possible values in the code are $b3(70%), $d1(82%) or $e4(89%) 
airCntMax        .EQU     $00a0                  ; Air count based on rpm, ect and iat, 8*airCntMax is used as a maximum on airCnt0 or when engine not rotating/starting to rotate 
accEnr           .EQU     $00a1                  ; Acceleration enrichment (100x/255)%. This value is actually  updated with min(airCnt0-oldAirCnt0,$48) under acceleration, see code. Max value is $48 from code
state3           .EQU     $00a2                  ; Flag register   
                                                 ;    bit 0 (0x01): Copied from same bit in state1 (1=startingToCrank)
                                                 ;    bit 1 (0x02): Copied from same bit in state1 (1=no pulse accumulator interrupts)
                                                 ;    bit 2 (0x04): Set when RPM exceeds threshold (rev limiter)
                                                 ;    bit 3 (0x08): Copied from same bit in state1 (1=rotatingStopInj)
                                                 ;    bit 4 (0x10): Copied from same bit in state1 (1=notRotating)
                                                 ;    bit 5 (0x20): Set if rotatingStopInj and not runningFast 
                                                 ;    bit 6 (0x40):
                                                 ;    bit 7 (0x80): Set to injFlags0.7 (1 when startingToCrankColdEngine)
injFactor        .EQU     $00a3   ;:$00a4        ; Global injector factor used to calculate injPw from [airCnt0:airCnt1],  
                                                 ; injFactor = 16*totMasComp * injComp/128 * [workFtrim + o2FuelAdj + 2*$80]/512 * iatCompFact/128 * baroFact/128 * openLoopEnr/128 * coldTempEnr/128  * (2*enrWarmup + $80)/128
oldReedVal       .EQU     $00a5                  ; Old value of the reed switch sensor
deadTime         .EQU     $00a6                  ; Injector deadtime in increment of 24uS (depends on current batteryVoltage)
injPw            .EQU     $00a7   ;:$00a8        ; 16 bit injector pulse width in microseconds. Logger reports high and low bytes: (.256 highByte)mS
inj1_offT        .EQU     $00a9   ;:$00aa        ; Injector #1? deactivation time (relative to timer t1t2_clk)  
inj3_offT        .EQU     $00ab   ;:$00ac        ; Injector #3? deactivation time (relative to timer t1t2_clk)  
inj4_offT        .EQU     $00ad   ;:$00ae        ; Injector #4? deactivation time (relative to timer t1t2_clk)  
inj2_offT        .EQU     $00af   ;:$00b0        ; Injector #2? deactivation time (relative to timer t1t2_clk)  
last_t1t2_clk    .EQU     $00b1                  ; Initialized to  t1t2_clk/256 on CAS falling edge, every one of them??? 
injToAct         .EQU     $00b2                  ; Indicate which injectors are currently active or should be activated, Set to 1 for an active injector 
                                                 ;    bit 0 (0x01): Inj 1?  
                                                 ;    bit 1 (0x02): Inj 3? 
                                                 ;    bit 2 (0x04): Inj 4? 
                                                 ;    bit 3 (0x08): Inj 2? 
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): 
                                                 ;    bit 6 (0x40): 
                                                 ;    bit 7 (0x80): 
tdcCasFlags      .EQU     $00b3                  ; Init to 5
                                                 ;    bit 0 (0x01): c0, c2:c1:c0 used as a down counter (on every CAS pulse falling edge) initialized with 5. Reset to 0 when the CAS pulse falling edge correpond to the cylinder #1 TDC pulse (see bit 7)
                                                 ;    bit 1 (0x02): c1
                                                 ;    bit 2 (0x04): c2
                                                 ;    bit 3 (0x08): Set to the last value of TDC bit on port3. 2
                                                 ;    bit 4 (0x10):
                                                 ;    bit 5 (0x20):
                                                 ;    bit 6 (0x40):
                                                 ;    bit 7 (0x80): Set to 1 when cylinder #1 TDC is detected on the CAS falling edge. Set to 1 when we detect that TDC bit on port3.2 has changed from 1 to 0 (falling edge) from one CAS falling edge to the other. That basically indicate cylinder #1 TDC  
casCylIndex      .EQU     $00b4                  ; Cas current cylinder index (0,1,2,3 -> cyl #2,#1,#3,#4). Counter looping from 0 to 3 and increased on every CAS falling edge. re-init to 0 when TDC of cylinder #1 is detected (tdcCasFlags.7 set). 
                                                 ;    bit 0 (0x01): 
                                                 ;    bit 1 (0x02): 
                                                 ;    bit 2 (0x04): 
                                                 ;    bit 3 (0x08): 
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): 
                                                 ;    bit 6 (0x40): 
                                                 ;    bit 7 (0x80): 
newInjToAct      .EQU     $00b5                  ; Indicate which injector should be activated (also, bit 7 is set when doing simultaneous injection). Mostly updated on the CAS falling edge
                                                 ;    bit 0 (0x01): Inj 1?  
                                                 ;    bit 1 (0x02): Inj 3? 
                                                 ;    bit 2 (0x04): Inj 4? 
                                                 ;    bit 3 (0x08): Inj 2? 
                                                 ;    bit 4 (0x10): Inj 5/6?
                                                 ;    bit 5 (0x20): Inj 5/6?
                                                 ;    bit 6 (0x40): 
                                                 ;    bit 7 (0x80): Set to 1 when when we should be doing simultaneous injection on all 4 cylinders, 0 indicate sequential injection
tdcCheck         .EQU     $00b6                  ; Init to 8 on the cas falling edge of the cylinder #1 TDC, decremented by 1 on every cas falling edge. Used to check that TDC sensor is working correctly, it should never reach 0...
oldInjToAct      .EQU     $00b7                  ; Old value of injToAct (before it was updated)
injToTest        .EQU     $00b8                  ; The current injector to test for proper operation (set to 1 to test), 1 bit per injector. Testing proceed from bit 0 to bit 3. We stay on the same injector if it is found to be bad, see around L1884
                                                 ;    bit 0 (0x01): Inj 1?  
                                                 ;    bit 1 (0x02): Inj 3? 
                                                 ;    bit 2 (0x04): Inj 4? 
                                                 ;    bit 3 (0x08): Inj 2? 
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): 
                                                 ;    bit 6 (0x40): 
                                                 ;    bit 7 (0x80): 
injBad           .EQU     $00b9                  ; Injector testing flags
                                                 ;    bit 0 (0x01): Set to 1 when one of the injector is not working correctly based on injector feedback bit, see injToTest
                                                 ;    bit 1 (0x02): Not used
                                                 ;    bit 2 (0x04): Not used
                                                 ;    bit 3 (0x08): Not used
                                                 ;    bit 4 (0x10): Not used
                                                 ;    bit 5 (0x20): Not used
                                                 ;    bit 6 (0x40): Not used
                                                 ;    bit 7 (0x80): Not used
obdInjCmd        .EQU     $00ba                  ; processing of OBD code bit 0 to 5 correspond to injectors being turned on/off                                                                                                    
                                                 ;    bit 0 (0x01): Inj. 1, Set to 0 if injector is currently turned off by obd command, 1 in normal operation 
                                                 ;    bit 1 (0x02): Inj. 3, See bit 0
                                                 ;    bit 2 (0x04): Inj. 4, See bit 0
                                                 ;    bit 3 (0x08): Inj. 2, See bit 0
                                                 ;    bit 4 (0x10): Inj 5/6 See bit 0
                                                 ;    bit 5 (0x20): Inj 5/6 See bit 0
                                                 ;    bit 6 (0x40): Not used 
                                                 ;    bit 7 (0x80): Not used
rtiCnt           .EQU     $00bb                  ; free counter increased on every real time interrupt (~800Hz), used to execute some functions only 1 out of N times (check count value)                                                         
rtiCnt48         .EQU     $00bc                  ; counter increased on every real time interrupt, maximum value is 2F (47), period 48.                                                                                                  
rtiReedFlags     .EQU     $00bd                  ; Flag register                                                                                                                                                                                 
                                                 ;    bit 0 (0x01): Bit is set in real time int. at 40Hz when T200_40Hz reach 0 (T200_40Hz loop from 5 to 0 at 200Hz)
                                                 ;    bit 1 (0x02): not used?
                                                 ;    bit 2 (0x04): not used?
                                                 ;    bit 3 (0x08): not used?
                                                 ;    bit 4 (0x10): not used?
                                                 ;    bit 5 (0x20): not used?
                                                 ;    bit 6 (0x40): not used?
                                                 ;    bit 7 (0x80): Latest reed switch value
                 
                 ;-------------------------------------------------
                 ; $be-$c2, series of timers (counting down to 0)
                 ; (see L1929) decremented in real time interrupt 
                 ; at ~200Hz
                 ;-------------------------------------------------
T200_40Hz        .EQU     $00be                  ; Loops from from 5 to 0 producing 40Hz for main loop (set rtiReedFlags.0)
T200_casRise     .EQU     $00bf                  ; Used by CAS interrupt as a timeout to validate the time in between CAS interrupts when RPM is very low and 16 bit timers roll over. Timer initialized on every cas rising edge
T200_casFall     .EQU     $00c0                  ; Used by CAS interrupt as a timeout to validate the time in between CAS interrupts when RPM is very low and 16 bit timers roll over. Timer initialized on every cas falling edge
T200_mas         .EQU     $00c1                  ; Used by the mas subroutine to know when the pulses are getting too close together (and we need to apply scaling). Re-initialized to 130ms on every airflow sensor interrupt (every pulse received)
T200_cop         .EQU     $00c2                  ; Used to toggle port6.5 if main loop executes at more than 20Hz, could be some sort of COP to reset ECU in case main loop goes slower than 20Hz.
                 
oldTps1          .EQU     $00c3                  ; Set to "old" TPS value for comparison with new during cranking?                                                                                                                   
vssCnt1          .EQU     $00c4                  ; Counter Initialized to $c8 every time the reed switch change value, decreased at real time int. frequency down to 0; Will be 0 only when when speed is lower than X (very slow speed?)
vssCnt2          .EQU     $00c5                  ; Counter used for speed sensor calculation, initialized to $E2, decreased on every call, speed = $E2-current value of this register                                                
vss              .EQU     $00c6                  ; "Vehicle speed sensor", actually computed from the reed switch transitions. Value is the period in 1/400sec of one complete reed switch square wave, approx 40cm. Speed in km/h is approximately given by 3.6*400*0.4/xx
oldTps2          .EQU     $00c7                  ;
tpsDiffMax1      .EQU     $00c8                  ; Maximum positive rate of change of tpsRaw seen during 1 main loop execution. (high value means driver is stepping on the gas, value of 0 means throttle is at constant position or decreasing). Set to the maximum value of tpsRaw-oldTps2 (updated at 100Hz) 
tempFlagTps      .EQU     $00c9                  ; Used as a temp flag during port2.2 activation/deactivation (aiflow sensor active filter reset???). Set to $ff when tpsRaw has increased by more than 1.5% and is between 26%-50%, $00 otherwise
L00ca            .EQU     $00ca                  ; Init to 6 but never used. Notice it is located in front of the 8 memories used to store ADC values? It also correspond to obd code $ca which erases all fault codes...
ectRaw           .EQU     $00cb                  ; Engine coolant temperature, see curve at beginning of file 
iatRaw           .EQU     $00cc                  ; Raw intake air temperature, see curve at beginning of file 
baroRaw          .EQU     $00cd                  ; Atmostpheric pressure: (.00486x)bar            
o2Raw            .EQU     $00ce                  ; Oxygen sensor (.0195x)v.                    
egrtRaw          .EQU     $00cf                  ; Exhaust gas recirculation temperature, unknown temperature curve, used this formula for now (-2.7x + 597.7)deg F              
battRaw          .EQU     $00d0                  ; Battery voltage (.0733x)v.                          
knockSensor      .EQU     $00d1                  ; Knock sensor                                
tpsRaw           .EQU     $00d2                  ; Throttle position sensor (100x/255)%               
ectFiltered      .EQU     $00d3                  ; This is the engine coolant tempterature that has been validated and then filtered to limit its rate of change to a few degrees per sec...
iatChecked       .EQU     $00d4                  ; Validated intake air temperature
baroChecked      .EQU     $00d5                  ; Verified barometer voltage, $cd=1bar
state2           .EQU     $00d6                  ;    bit 0 (0x01): Set if ectRaw >236 OR <5, FAULT VALUE = 30                                                                               
                                                 ;    bit 1 (0x02): Set if iatRaw >234 OR <14, FAULT VALUE = 123                                                                             
                                                 ;    bit 2 (0x04): Set if baroRaw >228 OR <100, FAULT VALUE = 205                                                                           
                                                 ;    bit 3 (0x08): Set when timer T40_mas expires, which means no pulse accumulator interrupt was received for over 0.3s-> no air is getting in or something wrong...
                                                 ;    bit 4 (0x10): Engine collant temp related?                                                                                                 
                                                 ;    bit 5 (0x20): Set to 1 if knock senor is not working???. Set to ^(port4Snap.5)
                                                 ;    bit 6 (0x40):                                                                                                                              
                                                 ;    bit 7 (0x80):                                                                                                                              
port3Snap0       .EQU     $00d7                  ; Loaded with port3 with some values reset by code depending on ???,                
                                                 ; used in idle speed calc? -> load that need to be considered in calc of idle speed 
                                                 ;    bit 0 (0x01): IG2 related, 0 when IG2 at +12V, ABS unit?  only used used for fuel trim on E931 only, see around Md4d4?                                                                     
                                                 ;    bit 1 (0x02): IG1 related? 0 when IG1 at +12V.                                                                                                                                            
                                                 ;    bit 2 (0x04): always reset to 0????
                                                 ;    bit 3 (0x08): Set to 1 if power steering pump is on
                                                 ;    bit 4 (0x10): AC switch (1=off) -> always set if ??? (config resistor???)                 
                                                 ;    bit 5 (0x20): Park/neutral -> always set by code???                                  
                                                 ;    bit 6 (0x40): 0 if key in start?
                                                 ;    bit 7 (0x80): idle position switch (1=on)?                                        
port4Snap        .EQU     $00d8                  ; Snapshot of port4 & 01111000
                                                 ;    bit 0 (0x01):                                                                     
                                                 ;    bit 1 (0x02):                                                                     
                                                 ;    bit 2 (0x04): 
                                                 ;    bit 3 (0x08): 1 when ECU test mode terminal grounded               
                                                 ;    bit 4 (0x10): 1 when timing terminal grounded                     
                                                 ;    bit 5 (0x20): knock sensor related (set indicates it works...)
                                                 ;    bit 6 (0x40): Fuel pump driven feedback?                      
                                                 ;    bit 7 (0x80): 
Tclocks          .EQU     $00d9                  ; State Flags for software counters, Updated from scratch (zero) on every main loop execution 
                                                 ;    bit 0 (0x01): Set at ~40Hz, set when 40Hz flag from real time interrupt was processed during loop (40Hz counters where decremented if required)
                                                 ;    bit 1 (0x02): Set at ~10Hz
                                                 ;    bit 2 (0x04): Set at ~2Hz, Used by heart beat mode
                                                 ;    bit 3 (0x08): Set at ~0.5Hz
                                                 ;    bit 4 (0x10): Not used?                                                       
                                                 ;    bit 5 (0x20): Not used?                                                       
                                                 ;    bit 6 (0x40): Not used?                                                       
                                                 ;    bit 7 (0x80): Not used?                                                       
rpm4             .EQU     $00da   ;:$00db        ; RPM/3.90625                                                       
rpm8             .EQU     $00dc                  ; RPM/7.8125                                                        
rpm31            .EQU     $00dd                  ; RPM/31.25 (engine rpm = RPM31p25 * 31.25)                         
airVol16         .EQU     $00de   ;:$00df        ; Air volume, 16 bit, airVol16 = [airCnt0:airCnt1] * masScalar/65536
airVol           .EQU     $00e0                  ; Air volume,  8 bit,   airVol = airVol16/2
airVolT          .EQU     $00e1                  ; Air volume,  8 bit,  airVolT = airVol16/2 * iatCompFact/128
airVolTB         .EQU     $00e2                  ; Air volume,  8 bit, airVolTB = airVol16/2 * iatCompFact/128 * baroFact/128
airVolB          .EQU     $00e3                  ; Air volume,  8 bit,  airVolB = airVol16/2 *    baroFact/128
mafRaw           .EQU     $00e4                  ; 8 bit airflow sensor pulse frequency  (6.25x)Hz, calculated from mafRaw16 (mafRaw = mafRaw16/64)
ftrimFlags       .EQU     $00e5                  ; Flag register for fuel trim???
                                                 ;    bit 0 (0x01): c0: c1c0 form the current trim range (00=low, 01=mid, 10=high) updated according to mafRaw16
                                                 ;    bit 1 (0x02): c1
                                                 ;    bit 2 (0x04): Set (E931 only) when speed exceed threshold (24km/h) with hysteresis, 
                                                 ;    bit 3 (0x08): Set (E931 only) if port3Snap0.0 & port3.0 are both set on E931 when speed exceed 24km/h?
                                                 ;    bit 4 (0x10): Set when rpm > L1983(xx) ~1000rpm with hysteresis  
                                                 ;    bit 5 (0x20): 
                                                 ;    bit 6 (0x40): 
                                                 ;    bit 7 (0x80):  Set when airVolT >24, reset when airVolT<=15. Theshold is 19.5 with +/-4.5 hysteresis
state1           .EQU     $00e6                  ; State flags mainly used to track engine start-up stages and running condition (not rotating, startingToCrank, etc.). Bits 0 to 4 will be clear when engine is running normally
                                                 ;    bit 0 (0x01): stage1 (startingToCrank?): 1 indicate engine is just rotating but no TDC signal seen yet????, reset to 0 once CAS/TDC??? or engine rpm>~400rpm
                                                 ;    bit 1 (0x02): no pulse accumulator interrupts ?: 1 indicate we did not receive a valid pulse accumulator interrupts for a long time, see state2
                                                 ;    bit 2 (0x04): stage3 (runningFast): 1 indicate the ECU has detected that the engine rpm was too high for current conditions?
                                                 ;    bit 3 (0x08): stage2 (rotatingStopInj): 1 indicate engine should be running or be started but something is preventing us from doing fuel injection (fuel cut, CAS not working, etc.). Injection could still proceed if runningFast is set
                                                 ;    bit 4 (0x10): stage0 (notRotating): 1 indicate state1 was calculated but nothing to report, set to 1 on init subr. reset to 0 when engine is rotating
                                                 ;    bit 5 (0x20): state1Calculated: 1 indicate state 1 was calculated, never reset?
                                                 ;    bit 6 (0x40): Not used?                                                                          
                                                 ;    bit 7 (0x80): closedLoop: 1 indicate closed loop mode, 0 indicate open loop                                  
injFlags0        .EQU     $00e7                  ; Flags related to injectors
                                                 ;    bit 0 (0x01): Flag is 0 on reset (meaning injectors interrupts not yet initiated?) and set to 1 once sInjPw is initialized. If required, first interrupt for injectors is also scheduled when initializing this flag to 1
                                                 ;    bit 1 (0x02): ??? 
                                                 ;    bit 2 (0x04): Set when rpm>=437.5
                                                 ;    bit 3 (0x08): ???
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): Set when temperature(ectFiltered) < -8degC, updated only when engine is notRotating
                                                 ;    bit 6 (0x40): 
                                                 ;    bit 7 (0x80): Set to 1 if startingToCrankColdEngine. Fuel should be injected simultaneously in all cylinders twice per rotation (every cas)
closedLpFlags    .EQU     $00e8                  ; Flags relaed to closed loop mode, 02 sensor, fuel trims
                                                 ;    bit 0 (0x01): Set to 1 when the air volume (airVolTB) is too high to use closed loop mode (first threshold) 
                                                 ;    bit 1 (0x02): Set to 1 when we should be using closed loop mode??? (might not use it anyway...)
                                                 ;    bit 2 (0x04): 
                                                 ;    bit 3 (0x08): 
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): 
                                                 ;    bit 6 (0x40): o2 sensor bad flag. Set to 1 when the o2 sensor voltage did not switch from lean to rich or rich to lean for a certain amount of time in closed loop. Also set to 1 if notRotating
                                                 ;    bit 7 (0x80): rich/lean flag, set to 1 o2Raw >= 0.6v (rich), Set to 0 if o2Raw < 0.6v (lean), updated once o2 sensor has warmed-up
o2Fbk            .EQU     $00e9   ;:$00ea        ; Oxygen feedback trim (16 bits actually used, most of the time only highest byte is used...) (.78x)% -> 100% = $80
o2Fbk_dec        .EQU     $00eb                  ; o2Fbk is decreased using this value when in closed loop and running rich
o2Fbk_inc        .EQU     $00ec                  ; o2Fbk is increased using this value when in closed loop and running lean
iscY0            .EQU     $00ed                  ; iscYn variables are short term correction factors/feedback for the isc step adjustment. It is centered at $80 (100%, no correction). A value higher than $80 indicate that we need to increase the isc step since the current rpm is lower than the desired one
                                                 ; The isc step used is increased/decreased by iscYn-$80
                                                 ; iscY0 is the ISC learning variable when A/C is off and PS is off, see iscPointers function. Value of $80=100% 
iscY1            .EQU     $00ee                  ; iscY1 is the ISC learning variable when A/C is on and PS is off, see iscPointers function. Value of $80=100%
iscY2            .EQU     $00ef                  ; iscY2 is the ISC learning variable when PS is on, see iscPointers function. Value of $80=100%
iscStepMax       .EQU     $00f0                  ; Maximum value applied to iscStepCurr in code
port3Snap1       .EQU     $00f1                  ; Loaded with port3Snap0 with some values set by code depending on ???,                
                                                 ;    bit 0 (0x01): IG2 related, 0 when IG2 at +12V, ABS unit?  only used used for fuel trim on E931 only, see around Md4d4?
                                                 ;    bit 1 (0x02): IG1 related? 0 when IG1 at +12V.                                                                        
                                                 ;    bit 2 (0x04): Set to 1 if vssCnt1 != 0 (car speed > 2.9km/h???)
                                                 ;    bit 3 (0x08): Set to 1 if power steering pump is on
                                                 ;    bit 4 (0x10): AC switch (1=off) 
                                                 ;    bit 5 (0x20): Park/neutral -> always set by code                                   
                                                 ;    bit 6 (0x40): 0 if key in start?                                                   
                                                 ;    bit 7 (0x80): idle position switch (1=on)?                                        
oldP3Snap1       .EQU     $00f2                  ; Old value of port3Snap1
iscLrnFlags      .EQU     $00f3                  ; Isc leanrning flags, all flags are reset to 0 in basic idle speed adjustment mode.  All flags except bit 0 are reset to 0 when notRotating or startingToCrank
                                                 ;    bit 0 (0x01): Set to 1 when engine is notRotating or startingToCrank, reset to 0 when engine is running
                                                 ;    bit 1 (0x02): 
                                                 ;    bit 2 (0x04): Set to 1 when the engine is running too slow? i.e. temperature(ectFiltered) > 55degC, rpm8 < 500rpm, engine is running, T40_acOnTrans is expired 
                                                 ;    bit 3 (0x08): 
                                                 ;    bit 4 (0x10): Set to 1 when conditions are good to update the isc leanrning variables.
                                                 ;    bit 5 (0x20): Set to 1 when iscStStall has been updated, i.e. when idle switch is off and iscFlags1.7 = 0 and rpm8>=500. Reset to 0 when iscStStall is reset to 0???
                                                 ;    bit 6 (0x40): 
                                                 ;    bit 7 (0x80): 
iscFlags1        .EQU     $00f4                  ; Flag register
                                                 ;    bit 0 (0x01): Set to 1 when engine not rotating or is running (basic idle speed adjustment mode is not active). Reset to 0 when key in start and iscStTargSpec = iscStepCurr
                                                 ;    bit 1 (0x02): 
                                                 ;    bit 2 (0x04): 
                                                 ;    bit 3 (0x08): 
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): Set to 1 when  engine StartingToCrank and temperature(iat) < 75degC. Only changed during startingToCrank. Used is setting isc step during cold engine startup
                                                 ;    bit 6 (0x40): 
                                                 ;    bit 7 (0x80): Set to 1 when tps has been high and airVol low for more than 0.5sec (tpsRaw >= 86% and airVol < $3a)
T_maxAdv         .EQU     $00f5                  ; E931 only, used to ramp down the effect of maxAdv 
maxAdv           .EQU     $00f6                  ; E931 only, maximum value of timing advance timingOct for E931 when engine is runningFast (timingOct is clipped to that value), T_maxAdv is used to ramp-down its effect with time
L00f7            .EQU     $00f7                  ; Unused?
varFlags0        .EQU     $00f8                  ; Various flags...
                                                 ;    bit 0 (0x01): Used in A/C cutoff for AT, 1 indicates TPS exceeded 82% the last time we checked it...
                                                 ;    bit 1 (0x02): Hot start flag, set to 1 when startingToCrank and open loop and temperature(iatChecked) >= 60degC and  temperature(ectFiltered) >= 93degC (hot start), used to increase fuel enrichement (reduce vapor lock maybe???)                              
                                                 ;    bit 2 (0x04): 
                                                 ;    bit 3 (0x08): 
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): Second priority, Set to 1 when purge solenoid is to be deactivated since min conditions for normal purge activation are not met
                                                 ;    bit 6 (0x40): First priority, Set to 1 when purge solenoid is to be activated by OBD command or normal activation criteria
                                                 ;    bit 7 (0x80): Third priority, Set to 1 when purge solenoid should be deactivated. This flag is toggled between 0 and 1 to implement pulsewidth modulation (very long period) of purge solenoid when the other two higher priority flags are not set  
fpsBcsFlags      .EQU     $00f9                  ; Flags related to fuel pressure solenoid and boost control solenoid
                                                 ;    bit 0 (0x01): 
                                                 ;    bit 1 (0x02): 
                                                 ;    bit 2 (0x04): Set to 1 when the fuel pressure solenoid was just deactivated (set to 1 only when bit 7 goes from 1 to 0). Reset to 0 at any other time
                                                 ;    bit 3 (0x08): Set to 1 when ECU decides that fuel pressure solenoid should be activated to reduce vapor lock 
                                                 ;    bit 4 (0x10): bcs, Set to 1 when mafRaw16 is above $4e ($4a for E932) with hysteresis, low threshold is $38
                                                 ;    bit 5 (0x20): bcs, Set to 1 when octane is above $c0 with hysteresis, low threshold is $9a
                                                 ;    bit 6 (0x40): bcs
                                                 ;    bit 7 (0x80): 
obdFlags         .EQU     $00fa                  ; Current state of diagnostic port command/query processing
                                                 ;    bit 0 (0x01): 1 toggle bit on every second "subroutine 1" loop                                                                                                                                                  
                                                 ;    bit 1 (0x02): 1 if serial output on port 2 is initialized.                                                                                                                                                      
                                                 ;    bit 2 (0x04): ?                                                                                                                                                                                                
                                                 ;    bit 3 (0x08): ?                                                                                                                                                                                                
                                                 ;    bit 4 (0x10): ?                                                                                                                                                                                                
                                                 ;    bit 5 (0x20): ?                                                                                                                                                                                                
                                                 ;    bit 6 (0x40): Set to 1 when a new OBD code was stored in obdCode? reset when obdCode has been processed.
                                                 ;    bit 7 (0x80): Set to 1 to indicate that a response to the query/command is being sent on the diagnostic port (new requests will be ignored)
obdActCmd        .EQU     $00fb                  ; processing of OBD code, contains which actuator is being currently processed. Set to 0 when actuator is off
                                                 ;    bit 0 (0x01): Purge solenoid
                                                 ;    bit 1 (0x02): Fuel pump
                                                 ;    bit 2 (0x04): Fuel pressure solenoid
                                                 ;    bit 3 (0x08): Egr solemoid
                                                 ;    bit 4 (0x10): Unused
                                                 ;    bit 5 (0x20): Boost control solenoid
                                                 ;    bit 6 (0x40): Unused
                                                 ;    bit 7 (0x80): Unused
validFlags       .EQU     $00fc                  ; Flag related to the validation of sensors...
                                                 ;    bit 0 (0x01): Set to 1 when T40_engRot is expired (no CAS interrupt received for a long time)  
                                                 ;    bit 1 (0x02): Set to 1 when the condition of the o2 sensor was determined (good or not). Only reset when car key is put in off I think
                                                 ;    bit 2 (0x04): Set to 1 when the condition of the egrt sensor was determined (good or not). Only reset when car key is put if off I think
                                                 ;    bit 3 (0x08): 
                                                 ;    bit 4 (0x10): 
                                                 ;    bit 5 (0x20): 
                                                 ;    bit 6 (0x40): 
                                                 ;    bit 7 (0x80): Set to 1 if o2Raw > 0.6V (rich), 0 otherwise 
iscStepTarg      .EQU     $00fd                  ; Target ISC step, that's the target value for iscStepCurr
idleSpdTarg      .EQU     $00fe                  ; Current target idle speed (xx*7.8125)rpm based on ect, A/C switch, etc.
airCntDef        .EQU     $00ff                  ; airCntDef*8*256 is the default value of [airCnt0:airCnt1:airCnt2] when mas interrupts are not being received, calculated from rpm, tps, ect, tables
injPwStart       .EQU     $0100   ;:$0101        ; The value of injPw used when engine is "rotating" (start-up). Calculated from fixed values (no air count)
oldFtrimFlg      .EQU     $0102                  ; Old value of ftrimFlags
accEnrDecay      .EQU     $0103                  ; Acceleration enrichment decay factor. accEnr is multiplied by (1-accEnrDecay/256) on each iteration. Initialized from a table as a function of ect.
accEnrTimer      .EQU     $0104                  ; Timer used to continue applying acceleration enrichement for 4 iterations after airflow is below minimum threshold (accEnrMinAf). 
accEnrMinAf      .EQU     $0105   ;:$0106        ; Minimum value of airCnt0 above/below which acceleration/deceleration enrichment should be applied (for acceleration, when airflow goes below, we stop applying acc enrichment after 4 iterations, see accEnrTimer. For decelaration, we stop reducing injPw as soon as we are above threshold)
decEnr           .EQU     $0107                  ; Deceleration enrichment (100x/255)%. This value is actually  updated with min(airCnt0-oldAirCnt0,$ff) under deceleration, see code. Max value is $ff from code
accEnrFact       .EQU     $0108   ;:$0109        ; Factor used in increasing injPw during acceleration enrichment
decEnrFact       .EQU     $010a   ;:$010b        ; Factor used in decreasing injPw during deceleration enrichment
accEnrDiffT      .EQU     $010c                  ; Minimum value of (airCnt0-oldAirCnt0) required to update decEnr or accEnr
accEnrTmr2       .EQU     $010d                  ; Timer used to hold accEnr for 4 or 5 iterations when it is getting small, before decreasing it to 0. 
oldTps3          .EQU     $010e                  ; Old value of tpsRaw calculated at 100Hz, used to compute tpsDiff100
tpsDiff100       .EQU     $010f                  ; Used to interpolate t_sInjEnr. Correspond to max(tpsRaw-oldTps3,0) calculated at 100Hz, used in the calculation of sInjEnr.
T200s_sInj       .EQU     $0110                  ; sInjEnr is reset to 0 when this timer expires (0.2sec after conditions don't warrant having sInjEnr anymore) 
sInjEnr          .EQU     $0111                  ; Kind of acceleration fuel enrichement when still using simultaneous injection?
sInjEnrMax       .EQU     $0112                  ; Maximum value applied to sInjEnr 
sInjTpsMax       .EQU     $0113                  ; sInjEnr is only increased if oldTps3 <= sInjTpsMax 
sInjPw           .EQU     $0114   ;:$0115        ; Injector pulsewidth used when simulataneous injection is used
sInjEnrInc       .EQU     $0116                  ; sInjEnr is increased by sInjEnrInc/128 * t_sInjEnr(tpsDiff100) = sInjEnrMax/32 * t_sInjEnr(tpsDiff100) at 100Hz under specific scenario
                 
                 ;----------------------------------------------------
                 ; $117-$132, series of software timers (counting down to 0)
                 ; decremented in subroutine 4 at ~40Hz
                 ;----------------------------------------------------
T40_2hz          .EQU     $0117                  ; set to $14 on init and loop at $14 (produces 2Hz)
T40_0p5hz        .EQU     $0118                  ; set to $50 on init and loop at $50 (produces 0.5Hz)
T40_start        .EQU     $0119                  ; Set to $ff when key in start, start counting when key no more in start?
T40_crank        .EQU     $011a                  ; Set to $ff when startingToCrank, starts counting when engine is no more startingToCrank (engine running or other state...)
T40_baro         .EQU     $011b                  ; Used to ignore barometric sensor input if battery<8V and 0.35s after battery>8V (baro sensor sensitive to voltage...). Sensor is ignore when timer is not 0
T40_stInj0       .EQU     $011c                  ; Starts counting from 1 sec when rotatingStopInj flag is activated. Used to activate T40_stInj1
T40_stInj1       .EQU     $011d                  ; Initialized to 2 sec when T40_stInj0 expires (ongoing rotatingStopInj for more than 1sec) starts counting when rotatingStopInj is deactivated. This timer is therefore non-zero 1 sec after rotatingStopInj starts and 2 sec after is stops
T40_o2Fbk        .EQU     $011e                  ; Timer will only be 0 when the low trim range will have been selected for more than 4 sec. Used to eventually calculate o2Fbk_dec,o2Fbk_inc, how fast o2 feedback is adjusting...
T40_ftrim2       .EQU     $011f                  ; Used on E931 as an additional condition to update fuel trims
T40_engRot       .EQU     $0120                  ; Kind of an "engine rotating" flag, This timer is re-initialized to 0.6s or 1.2s on every CAS interrupt, will reach 0 only if no CAS int. is received (engine not rotating or very slowy) for more than that time (rpm<0.83/K???)
T40_mas          .EQU     $0121                  ; This timer is periodically initialized to 12 (0.3s) and will reach 0 only if no mas interrupt is received for that long (no air is getting in or something is wrong...)
T40_fuelCut      .EQU     $0122                  ; Fuel cut timer, fuel cut is applied only when this timer reach 0: After air flow threshold is exceeded for more than 1s
T40_ftrim        .EQU     $0123                  ; Fuel trim update timer. Fuel trim are not updated unless this timer is expired (=0). It is set to 5 sec when condition are stable, i.e. fuel trim are update only after conditions are stable for more than 5 sec
T40_noPower      .EQU     $0124                  ; Timer is init at 0.125sec on every loop when ECU receives power? Will reach 0 when the ECU is about to turn-off (ECU relay turns-off after a few seconds...)
T40_revving      .EQU     $0125                  ; Timer used in updating iscStStall. Re-init to 0.5sec if  tpsRaw < 86% or airVol >= $3a. Timer will start counting when tpsRaw>86% and airVol < $3a and will expire 0.5sec later. Keeps track of rapid throttle plate opening in stalling calculations???
T40_iscLrn       .EQU     $0126                  ; Timer looping at 40 (produces 1 Hz) used to update isc0/isc1 and iscY1/iscY2/iscY3 at 1Hz (isc learning...)
T40_stall        .EQU     $0127                  ; Used to update iscStStall at ~2Hz
T40_acOnTrans    .EQU     $0128                  ; Used to filter out (0.1sec) the impact of A/C being turned-on (transcient load) when evaluating whether the engine is running too slow (<500rpm) 
T40_iscStart     .EQU     $0129                  ; Used to decrement iscStStartMaster as a function of time upon engine startup
T40_checkTargRpm .EQU     $012a                  ; Timer used to schedule every 1sec the comparison between current rpm to target rpm and adjust isc if necessary
T40_iSpAdj       .EQU     $012b                  ; Timer is 0 when Idle speed adjustment mode is active. Set to 0.2sec after both timing adjustment and ECU test mode terminals are grounded. i.e. idle speed adjustement mode is applied 0.2sec after terminals are grounded...
T40_21           .EQU     $012c                  ; For E932, used to decrement iscStBaseAcAdj at 2.22Hz
T40_obdCmd       .EQU     $012d                  ; Implement the processing of OBD command code, set to $f0 (6 seconds at 40Hz) if an injector is off or an actuator on
T40_acOn         .EQU     $012e                  ; Implement min time before engaging A/C clutch after A/C button is pressed
T40_acOnRpm      .EQU     $012f                  ; Implement min time before engaging A/C clutch after RPM > 438 (after car is started-up)
T40_acCut        .EQU     $0130                  ; Implement the 5s A/C cutoff when TPS goes above (and stays above) 82% in AT (5 sec countdown)
T40_26           .EQU     $0131                  ; Unused (but decremented...)
T40_27           .EQU     $0132                  ; Unused (but decremented...)
                 
                 
                 ;-----------------------------------------
                 ; Software timer at ~40Hz decremented individually
                 ;-----------------------------------------
T40s_Idle        .EQU     $0133                  ; Only decremented under some specific conditions, init with $1e(0.75s) when idle switch is off, will reach 0 when idle switch has been on for more than 0.75s, used to condition idle flag with A/C switch. 
                 
                 ;----------------------------------------------------
                 ; $134-$13f, series of software timers (counting down to 0)
                 ; decremented in subroutine 4 at ~2Hz
                 ;----------------------------------------------------
T2_crank         .EQU     $0134                  ; Set to $ff when startingToCrank, starts counting when engine is no more startingToCrank (engine running or other state...)
T2_EcuPower      .EQU     $0135                  ; Starts counting from $ff when the ECU receives power, used to blink the "check engine" light when the ECU is turned on. 
T2_closedLp      .EQU     $0136                  ; Used to prolong closed loop mode when we go over an airVolTB threshold for a short period of time, Init to 12sec or 20sec
T2_o2Sensor      .EQU     $0137                  ; Used to validate the o2 sensor voltage. If timer expires with the o2 sensor voltage never switching (rich/lean) then o2 sensor is not working correctly...
T2_hotEnrich     .EQU     $0138                  ; Used for fuel enrichement during 120sec after starting engine under very hot intake air temperature (reduce vapor lock???)
T2_airVolT       .EQU     $0139                  ; Set to 5 sec whenever airVolT>24. Will expire once airVolT<=15 for more than 5sec
T2_6             .EQU     $013a                  ; Unused? (but decremented...)
T2_snsrChk       .EQU     $013b                  ; Sensor is flagged as bad only when it has been consistently been tested as bad for 4sec. T2_snsrChk implement that 4sec. Initialized to 4 sec everytime sensrChkIdx is reset to 0
T2_o2Chk         .EQU     $013c                  ; Used in o2 sensor testing/validation. re-initialized to 30sec as long as all the testing pre-conditions are not met or as long as we are running rich. Starts counting when we are running lean and pre-conditions are met...
T2_egrtChk       .EQU     $013d                  ; Used in egrt sensor testing/validation.
T2_stCrank       .EQU     $013e                  ; Init to $ff when startingToCrank or when engine just started rotating, starts counting after state change 
T2_11            .EQU     $013f                  ; Unused? (but decremented...)
                 
                 ;---------------------------------------------------
                 ; 140-144, series of software timers (counting down to 0)
                 ; decremented in subroutine 4 at ~0.5Hz
                 ;---------------------------------------------------
T0p5_crank1      .EQU     $0140                  ; Set to $ff when startingToCrank, starts counting when engine is no more startingToCrank (engine running or other state...)
T0p5_crCold      .EQU     $0141                  ; Basically not null for 120sec after a cold engine is being cranked/started. Initialized to 120sec when startingToCrank and temperature(ectFiltered) <= 88degC or to 0 if startingToCrank and temperature(ectFiltered) >88degC. Never updated otherwise. Starts counting when we are not startingToCrank. Reset to 0 when notRotating. 
T0p5_purge       .EQU     $0142                  ; Used to implement pulsewidth modulation of the purge solenoid (if some conditions are met), period is very long, 236sec
T0p5_crank2      .EQU     $0143                  ; Similar to T0p5_crank1
T0p5_ect         .EQU     $0144                  ; Reloaded with 5 min on every loop. Starts counting from 5 min only when ect equals exactly 41degC, used in ECT sensor fault routine. Since ect should not stay at that temp for long, counter should never reach 0???
                 
Tcas             .EQU     $0145   ;:$0146        ; Tcas (125KHz clock, half the real clock...) is the time(s) per cas interrupt * 125000, rpm = 60/(2*Tcas/125000), Tcas = 60/(2*rpm/125000)    (there are 4 cas interrupt for every 2 engine rotations). Tcas is calculated from [TcasLast0:TcasLast1]/2
TcasOld          .EQU     $0147   ;:$0148        ; previous value of Tcas
airDiffPos1      .EQU     $0149                  ; airDiffPos is transfered to it in subroutine 1
airDiffNeg1      .EQU     $014a                  ; airDiffNeg is transfered to it in subroutine 1
mafRaw16         .EQU     $014b   ;:$014c        ; 16 bit mafRaw, Airflow sensor pulse frequency (x/10.24)Hz, calculated from filtered air count (airCnt0:airCnt1) and rpm
tpsDiffMax2      .EQU     $014d                  ; Value tpsDiffMax1 is transfered here on every main loop execution    
ectCond          .EQU     $014e                  ; Conditionned ect for table interpolation, calculated from ectFiltered, see around L1035 
iatCond          .EQU     $014f                  ; Condtionned intake air temperature -> validated and offset/clipped  = max(min(iatChecked,$e0)-$20,0)     
airVolCond       .EQU     $0150                  ; Conditionned airVol used in table interpolation
rpmIndex1        .EQU     $0151                  ; Set to min(max(RPM31p25-500rpm,0),4500rpm), used in 2D interpolation of t_egrDutyFact (column) 
baroCond         .EQU     $0152                  ; Conditionned barometric pressure, non-linear range of $00 to $80 (0.45bar to 0.92bar): 1:1 from $00 to $40 and 2:1 from $40 to $80 
injMasComp       .EQU     $0153   ;:$0154        ; totMasComp*16 * injComp/128
totMasComp       .EQU     $0155   ;:$0156        ; Total mas compensation factor, (masComp+t_masComp(xx))* masLinComp/128
masLinComp       .EQU     $0157                  ; Interpolated t_masLin, compensate for airflow sensor non-linearity as a function of iat, baro and airflow sensor frequency
L0158            .EQU     $0158                  ; Not used????
openLoopEnr      .EQU     $0159                  ; Open loop enrichement factor, based on timing/knock fuel enrichment conditionned on tps and timer based enrichement
o2FuelAdj        .EQU     $015a                  ; Factor to increase/reduce fuel depending on o2 sensor voltage/feedback, value from 0 to 255, $80=100%->no fuel adjustment. o2FuelAdj = o2Fbk +/-  t_closedLpV1(xx) or t_closedLpV2(xx)
workFtrim        .EQU     $015b                  ; Working fuel trim, the fuel trim selected according to current fuel trim range
coldTempEnr      .EQU     $015c                  ; Fuel enrichement factor for cold engine under low airflow conditions, Value of $80=100% means no enrichement
enrWarmup        .EQU     $015d                  ; Current fuel enrichment during warmup/startup, enrichement factor = (2*enrWarmup+$80)/$80
T_enrWarm        .EQU     $015e                  ; Counter used to lower enrWarmup as a function of time down to 0 
iatCompFact      .EQU     $015f                  ; Air density factor as a function of temperature ($80=1.0)
baroFact         .EQU     $0160                  ; Barometric pressure factor, pressure=(baroFact/128)bar
timFuelEnr       .EQU     $0161                  ; Fuel enrich based on knock/timing??? (Temporarily the timing map value)
T40s_iscStable   .EQU     $0162                  ; Timer is re-initialized to various values (highest of new and current is kept) every time a ISC impacting load is detected (i.e power steering pump is turned on). Timer is decremented only when iscStepTarg=iscStepCurr, i.e. idle speed target is reached. 
                                                 ; It will therefore reach 0 only when the ISC step has reached its target and stayed there for a while, ISC is stable...
iscStStall       .EQU     $0163                  ; This is the minimum isc step to use when the idle switch transition from off to on. It is decreased by 3 at ~20Hz???. I suppose this is to smooth the rapid change of airflow when the throttle plate closes and reduce the possibility of stalling the engine
iscStStartUsed   .EQU     $0164                  ; This is the current value of the offset to add to base isc step when the engine was just started. It is slowly decreased (following iscStStartMaster) until the isc step stabilizes. It then stays constant. Whatever value remains after stabilization is used to update iscYn learning variables
iscLowBatt       .EQU     $0165                  ; Keep track of battery condition for ISC spindle updating. Bit 7 is set when battRaw >= 10V (with hysteresis). 2 lower bits used as counter (3 max) as to how many consecutive times battRaw >= 10V, ISC spindle is not moved until this counter is $03
iscStTargSpec    .EQU     $0166                  ; The value that will be stored in iscStepTarg when the engine is runnning but iscLrnFlags.1 is set
iscStBase        .EQU     $0167                  ; Basic ISC step as a function of ECT
iscStBaseAc      .EQU     $0168                  ; iscStBase corrected for A/C and transmission load
iscStBaseCSt     .EQU     $0169                  ; iscStBase corrected for cold start period, i.e. high ISC step at start and then decreasing towards iscStBase over 120sec. Set to 0 after 120sec
iscStBarOff      .EQU     $016a                  ; Offset to add to the basic ISC step to compensate for barometric pressure
iscStBaseAcAdj   .EQU     $016b                  ; For E932, used to adjust iscStBaseAc when transmission is engaged, i.e. drive, decremented down to 0 at 2.22Hz...  
idleSpdInit      .EQU     $016c                  ; Preliminary idle speed target (xx*7.8125)rpm, t_idleSpd(ect) or t_idleSpdDr(ect), used in the computation of idleSpdTarg
idleSpdMin       .EQU     $016d                  ; Minimum idle speed target (xx*7.8125)rpm, used in the computation of idleSpdTarg
L016e            .EQU     $016e                  ; Unused?
advTotal         .EQU     $016f                  ; Sum of the timing (xx-10)degrees BTDC from the timing maps (timingOct) and of three other timing corrections (advEct-$80, advIat-$80, advRpm-$80)
timingOct        .EQU     $0170                  ; Base timing (xx-10)degrees corrrected for octane: timingOct = alpha * t_timingHiOct(rpm, load) + (1-alpha) * t_timingLoOct(rpm, load)    where alpha = octane/255
advEct           .EQU     $0171                  ; Ect based timing correction (xx-$80)degrees
advIat           .EQU     $0172                  ; Iat based timing correction (xx-$80)degrees
advRpm           .EQU     $0173                  ; Rpm based timing correction (xx-$80)degrees
coilChkCnt       .EQU     $0174                  ; Used to set an error flag if the ignition coil sensing circuit shows that the ignition is not working properly 
coilHist         .EQU     $0175                  ; coilHist basically contains the ignition coil sensing circuit history (0 or 1 from port4.2) for the last 8 CAS interrupts, bit 7 being the oldest and bit 0 the newest
T40s_octane      .EQU     $0176                  ; octane timer decremented at 40Hz and looping at $10. octane is updated when timer reaches 0 (at 2.5Hz total)
knockTimer       .EQU     $0177                  ; Used in the validation of the raw knock sensor voltage received from the ADC
egrtTimerThr     .EQU     $0178                  ; Timer threshold (compared to T0p5_crank2) used to decide whether enough time has elapsed to test the egrt sensor (180sec or 360sec), threshold is ect based
sensrChkIdx      .EQU     $0179                  ; The current index in table t_snsrChk indicating which sensor is to be checked/tested next.
obdCode          .EQU     $017a                  ; Contain the latest code received from OBD connector
errCodeIdx       .EQU     $017b                  ; Processing of diagnoctic port error code output (heart beat mode), 
                                                 ; c4:c3:c2:c1:c0 is the index of the current error being output
                                                 ; d2:d1:d0 are used as a small 2Hz timer to produce the "heart beat"...
                                                 ;     bit 0 (0x01): c0 
                                                 ;     bit 1 (0x02): c1
                                                 ;     bit 2 (0x04): c2
                                                 ;     bit 3 (0x08): c3
                                                 ;     bit 4 (0x10): c4
                                                 ;     bit 5 (0x20): d0
                                                 ;     bit 6 (0x40): d1
                                                 ;     bit 7 (0x80): d2
errCodeProc      .EQU     $017c                  ; Loaded with the error code (t_snsrChkCode) being output to the test connector (heart beat mode) and then updated as the code is being output.
                                                 ;     bit 0 (0x01): a0  a3:a2:a1:a0 is the number of short pulse left to output to connector
                                                 ;     bit 1 (0x02): a1
                                                 ;     bit 2 (0x04): a2
                                                 ;     bit 3 (0x08): a3
                                                 ;     bit 4 (0x10): b0 b2:b1:b0 is the number of long pulse left to output to connector
                                                 ;     bit 5 (0x20): b1
                                                 ;     bit 6 (0x40): b2
                                                 ;     bit 7 (0x80): c0 Set to 1 when a new code is loaded, reset to 0 at midpoint between long and short pulses
egrDuty128       .EQU     $017d                  ; EGR solenoid Duty cycle value from 0 to $80 produces 0 to 100% (not sure of correspondance)
egrDuty          .EQU     $017e                  ; EGR solenoid Duty cycle (48-value)/48, value of table at FF88 interpolated by ECT
bGaugeODuty      .EQU     $017f                  ; Boost gauge "off-duty" cycle, value between $00 and $18, $00 corresponding to the maximum of the boost gauge scale
T40s_bcs         .EQU     $0180                  ; bcs timer, decremented at 40Hz, loops at $14 (20), bcs duty cycle is updated when this timer reaches 0 (at 2Hz)
bcsDuty          .EQU     $0181                  ; bcs duty cycle, duty cycle = (48-value)/48
T40s_tps         .EQU     $0182                  ;
ectStCrank       .EQU     $0183                  ; Loaded with ectFiltered when engine is startingToCrank, used in ect sensor check
rpmX4Filt        .EQU     $0184   ;:$0185        ; Filtered version of 16*rpm4 (xx*16/3.90625)rpm. Filtering is achieved using exponential averaging with alpha = 0.90625
injCount         .EQU     $0186                  ; Used in the calculation of injPwStart. Incremented by 1 (255 max) every time injPw !=0 in interrupt rountine (fuel is injected)
airCntMin0       .EQU     $0187                  ; [airCntMin0:airCntMin1] is the minimum value of [airCntNew0:airCntNew1] before it is used for airCnt0 calcuations
airCntMin1       .EQU     $0188                  ; See airCntMin0


                  ;------------------------------------------------------------
                  ; Unused memory block, except for iscStStartMaster
                  ;
                  ; Also provides a buffer space in case of stack overflow...
                  ; Memories should always be 0 else it means the stack 
                  ; overflowed in this region... 
                  ;------------------------------------------------------------
L0189            .EQU     $0189                  ;
L018a            .EQU     $018a                  ;
L018b            .EQU     $018b                  ;
L018c            .EQU     $018c                  ;
iscStStartMaster .EQU     $018d                  ; This is the master isc step offset used upon engine startup. It is initialized with a value from table and then decreased as a function of time down to 0. See iscStStartUsed for more details...
L018e            .EQU     $018e                  ;
L018f            .EQU     $018f                  ;
L0190            .EQU     $0190                  ; Memory cleared up to (and including) here
ramClearEnd      .EQU     $0190                  ;
                 
                  ;--------------------------------------------
                  ; Memory below is reserved for the stack
                  ;--------------------------------------------
L0191            .EQU     $0191                  ;                             
L0192            .EQU     $0192                  ; 
L0193            .EQU     $0193                  ; 
L0194            .EQU     $0194                  ; 
L0195            .EQU     $0195                  ; 
L0196            .EQU     $0196                  ; 
L0197            .EQU     $0197                  ; 
L0198            .EQU     $0198                  ; 
L0199            .EQU     $0199                  ; 
L019a            .EQU     $019a                  ; 
L019b            .EQU     $019b                  ; 
L019c            .EQU     $019c                  ; 
L019d            .EQU     $019d                  ; 
L019e            .EQU     $019e                  ; 
L019f            .EQU     $019f                  ; 
L01a0            .EQU     $01a0                  ; 
L01a1            .EQU     $01a1                  ; 
L01a2            .EQU     $01a2                  ; 
L01a3            .EQU     $01a3                  ; 
L01a4            .EQU     $01a4                  ; 
L01a5            .EQU     $01a5                  ; 
L01a6            .EQU     $01a6                  ; 
L01a7            .EQU     $01a7                  ; 
L01a8            .EQU     $01a8                  ; 
L01a9            .EQU     $01a9                  ; 
L01aa            .EQU     $01aa                  ; 
L01ab            .EQU     $01ab                  ; 
L01ac            .EQU     $01ac                  ; 
L01ad            .EQU     $01ad                  ; 
L01ae            .EQU     $01ae                  ; 
L01af            .EQU     $01af                  ; 
L01b0            .EQU     $01b0                  ; 
L01b1            .EQU     $01b1                  ; 
L01b2            .EQU     $01b2                  ; 
L01b3            .EQU     $01b3                  ; 
L01b4            .EQU     $01b4                  ; 
L01b5            .EQU     $01b5                  ; 
L01b6            .EQU     $01b6                  ; 
L01b7            .EQU     $01b7                  ; 
L01b8            .EQU     $01b8                  ; 
L01b9            .EQU     $01b9                  ; 
L01ba            .EQU     $01ba                  ; 
L01bb            .EQU     $01bb                  ; 
L01bc            .EQU     $01bc                  ; 
L01bd            .EQU     $01bd                  ; 
L01be            .EQU     $01be                  ; 
stack            .EQU     $01bf                  ; Top of stack location(grows backward (push-> SP=SP-1)
            
  
                            
;***************************************************************
;*
;*
;* Unused/Unavailable memory?
;*
;*
;***************************************************************
empty1      .EQU    $01C0   ;:$01FF



;******************************************************************
;
;
; 32KB chip address range start
;
;
;******************************************************************
epromStart   .org    $8000



;******************************************************************
;
;
; Battery gauge code
;
; 0psi boost ~12.14V ~ 40% duty
;
;
;
;******************************************************************
            .fill   newCode-$, $ff
newCode     .org    $CB00
#ifdef batteryGauge
battGauge   ldab    battRaw                   ; b=battery voltage
            subb    #$8C                      ; remove 10.262V
            lsrb                              ;
            lsrb                              ;
            tba                               ;
            lsrb                              ;
            aba                               ;
            tab                               ; b = 3/8*(Vbatt-10.262v), gives a effective range of 10.262V to 14.95V (0 to 24 in boost gauge range)
            rts
#endif



;******************************************************************
;
;
; Empty space
;
;
;******************************************************************
            .fill   codeStart-$, $ff



;******************************************************************
;
;
; Start of code after reset
;
;
;******************************************************************
codeStart   .ORG    $ceff-codeOffset
            jmp     reset


;******************************************************************
;
;
; Empty space
;
;
;******************************************************************
empty2      .fill   obdTable-empty2, $ff



;******************************************************************
;*
;* OBD interface queries, commands
;*
;*   Codes from $00 to $3d: Regular queries, return the value of the
;*                variables showed in obdTable located below, 
;*                see each variable definition... First value in table 
;*                correspond to obd query code $00, increases by 1 
;*                for each table value
;*     
;*   Codes from $3e to $3f: Converted to $3d, see that obd code
;*
;*   Codes from $40 to $c9: Returns what is stored in that ram address
;*
;*   Codes from $ca to $ca:: Erase all fault codes and returns $00 if
;*                           engine not rotating. If engine is rotating, all 
;*                           actuators/injector commands are reset and $ff
;*                           is returned.
;* 
;*   Codes from $cb to $f0: Returns what is stored in that ram address
;*
;*   Codes from $f1 to $fc: Injector/actuators commands, returns $ff if 
;*                          successfull
;*         
;*         $f1: Activate boost control solenoid
;*         $f2: Unused in code        
;*         $f3: Activate egr solemoid          
;*         $f4: Activate fuel pressure solenoid
;*         $f5: Activate purge solenoid       
;*         $f6: Turn on fuel pump     
;*         $f7: Disable injector #6 (inoperative in code)  
;*         $f8: Disable injector #5 (inoperative in code)  
;*         $f9: Disable injector #4 
;*         $fa: Disable injector #3 
;*         $fb: Disable injector #2 
;*         $fc: Disable injector #1 
;*
;*   Codes from $f1 to $ff: Special queries
;*
;*         $fd: Serial link test, returns $b5 (E931) or $b7 (E932)
;*         $fe: resistor strapping low word from t_strap3
;*         $ff: resistor strapping high word from t_strap3
;*     
;******************************************************************
            .org $d000-codeOffset
obdTable    .byte   port1,         port2,       port3,       port4            ; obd $00 to $03 
            .byte   port5,         port6,       timingAdv,   ectRaw           ; obd $04 to $07
            .byte   isc0,          iscY0,       isc1,        iscY1            ; obd $08 to $0b
            .byte   ftrim_low,     ftrim_mid,   ftrim_hi,    o2Fbk            ; obd $0c to $0f
            .byte   ectFiltered,   iatChecked,  egrtRaw,     o2Raw            ; obd $10 to $13
            .byte   battRaw,       baroRaw,     iscStepCurr, tpsRaw           ; obd $14 to $17
            .byte   closedLpFlags, ftrimFlags,  mafRaw,      ftrim_low        ; obd $18 to $1b
            .byte   airVol,        accEnr,      state1,      ftrim_low        ; obd $1c to $1f
            .byte   rpm8,          rpm31,       port3Snap1,  iscLrnFlags      ; obd $20 to $23
            .byte   idleSpdTarg,   iscStepTarg, knockSum,    port3Snap0       ; obd $24 to $27
            .byte   port4Snap,     injPw,       injPw+1,     enerLen          ; obd $28 to $2b
            .byte   airCnt0,       airCnt1,     injFactor,   injFactor+1      ; obd $2c to $2f
            .byte   iscFlags0,     temp1,       temp2,       temp3            ; obd $30 to $33
            .byte   temp4,         temp5,       o2BadCnt,    egrtBadCnt       ; obd $34 to $37
            .byte   faultHi,       faultLo,     iatRaw,      stFaultHi        ; obd $38 to $3b
            .byte   stFaultLo,     ftrim_low                                  ; obd $3c to $3d



;******************************************************************
;
;
; Code executed after reset
;
;
;******************************************************************
reset       lds     #stack                    ; Set the stack pointer                                       
            bsr     ecuInit                   ; Initialization branch                                       
                                                                           
            ;---------------------------------------------                                                       
            ; Main ECU loop executed in low priority
            ; (compared to interrupt code). Loop will
            ; execute slower when the computing load
            ; increases...A minimum of 20Hz is monitored
            ; by the COP function? 
            ;---------------------------------------------                                                       
L1001       jsr     subroutine1                ; 
            jsr     subroutine2                ; 
            jsr     subroutine3                ; 
            jsr     subroutine4                ; 
            jmp     L1001                      ; 



;******************************************************************
;
;
; Initialization subroutine
;
;
;******************************************************************
            ;------------------------------------------------------------------                       
            ; Init all outputs  (port1, port2 port5 and port6) to known states
            ;------------------------------------------------------------------                       
ecuInit     ldd     #$bf0f                    ;                               
            std     port1                     ; port1 = 1011 1111, port2 = 0000 ffff                             
            orm     port5, #$ff               ; port5 = 1111 1111
            andm    port6, #$00               ; port6 = 0000 0000

            ;-------------------------------------------------------------                       
            ; Init port1 through port5 data direction registers
            ; Init real time interrupt frequency
            ; Init L000f, L0017 and L0024 to 0 (never used in the code???)
            ;-------------------------------------------------------------                       
            jsr     initFunc1                 ;                                  
            ldd     #$1b3d                    ;                               
            staa    t1_csr                    ; t1_csr = 0001 1011, enable injectors and cas interrupts, disable injectors, set cas detection edge polarity?
            stab    t2_csr                    ;                               
            ldd     #$5e0a                    ;                               
            std     t3_csr0                   ; t3_csr0 = 0101 1110, t3_csr1 = 0000 1010, both coils not energized                             
            jsr     init_t1_t2                ;                                   
                                                                       
            ;-----------------------------------------------------------                       
            ; Clear RAM from ramClearStart to ramClearEnd inclusively   
            ;-----------------------------------------------------------                       
#ifndef noRamReset
            ldy     #ramClearStart            ;                             
            clra                              ;                             
            clrb                              ;                             
L1003       std     $00,y                     ; Operation does y = y + 2                                               
            cmpy    #ramClearEnd+1            ;                                             
            bcs     L1003                     ;                              
#endif
                                                                       
            ;------------------------------------------------
            ; Read all 8 ADC ports values and store in ram
            ;------------------------------------------------
            ldy     #ectRaw                   ;                                
            ldaa    #$08                      ; start with port 0 and start bit set ($08)                          
L1004       psha                              ;                           
            jsr     readAdc2                  ;                              
            stab    $00,y                     ; y = y + 1                          
            pula                              ;                           
            inca                              ;                           
            cmpa    #$10                      ;                           
            bcs     L1004                     ;                           

            ;-------------------------------------------------------
            ; Check if all ISC variables are initialized properly
            ; If not then re-initialize ECU from scratch
            ;-------------------------------------------------------
            ldx     #$b000                    ;                           
            cpx     isc0                      ;                          
            bcs     L1005                     ; Branch to re-initialize ECU from scratch 
            cpx     isc1                      ;                             
            bcs     L1005                     ; Branch to re-initialize ECU from scratch                             
            ldx     #$6c00                    ;                               
            cpx     isc0                      ;                             
            bhi     L1005                     ; Branch to re-initialize ECU from scratch                              
            cpx     isc1                      ;                             
            bhi     L1005                     ; Branch to re-initialize ECU from scratch                             
            ldaa    iscStepCurr               ;                                    
            cmpa    #$87                      ;                             
            bhi     L1005                     ; Branch to re-initialize ECU from scratch                             
            coma                              ;                             
            anda    #$7f                      ;                             
            cmpa    iscStepCom                ;                                   
            bne     L1005                     ; Branch to re-initialize ECU from scratch                             

            ;-----------------------------------------------------------
            ; All ISC variables look OK
            ; Check if ram control register was erased (loss of power)
            ;-----------------------------------------------------------
            ldab    ramControl                ;                              
#ifdef octaneReset                            ;
            bmi     L1006a                    ;
#else                                         
            bmi     L1006                     ; Branch if ramControl.7 set, i.e. we already did a fresh reset and power was not lost
#endif
                                                            
            ;------------------------------------------------------
            ; Perform a fresh reset, i.e. init ECU from scratch
            ;------------------------------------------------------
            ;---------------------------------------
            ; Reset all faults and fault counters
            ;---------------------------------------
L1005       clra                              ;                             
            clrb                              ;                             
            std     stFaultHi                 ;                                  
            std     faultHi                   ;                                
            std     o2BadCnt                  ;                                 

            ;--------------------
            ; Init ISC variables
            ;--------------------
            ldaa    #$80                      ;                             
            staa    iscFlags0                 ; iscFlags0 = $80, isc max calibration is requested                                 
            clra                              ;                             
            jsr     iscStepComp               ; iscStepCurr = $0, iscStepCom = (~$0 & 7F)                                    
            ldd     #$8c00                    ;                               
            std     isc0                      ; isc0 = $8c                            
            std     isc1                      ; isc1 = $00

            ;-------------------------------------------------------------                                      
            ; Set isc coil pattern and pattern index to t_iscPattern(0)
            ;-------------------------------------------------------------                                      
            ldab    #$04                      ;                             
            stab    iscPatrnIdx               ; iscPatrnIdx = $04 (lower two bits = 00b)                              
            orm     port5, #$80               ; ISC coil pattern bit 6 and 7 = 10b = t_iscPattern(0)                               
            andm    port5, #$bf               ; ISC coil pattern bit 6 and 7 = 10b = t_iscPattern(0)                               

            ;-------------------------------------------------------------                                      
            ; Init fuel trim to 100% and ftrimCntr to $80 
            ;-------------------------------------------------------------                                      
            ldaa    #$80                                                 
            tab                                                          
            std     ftrim_low                                                 
            std     ftrim_hi                                                 

            ;------------------------------------
            ; Init octane to max, i.e. good fuel
            ;------------------------------------
L1006a      ldaa    #$ff                    ; Reset octane value to max value (good fuel, no knock)
            staa    octane                                                 

            ;-------------------------------------------------
            ; Set the ramControl flag bits since 
            ; fresh reset steps are (or were already) done
            ;-------------------------------------------------
L1006       ldaa    #$c0                    ;                             
            staa    ramControl              ;              
                                 
            ;-----------------------------------------
            ; Init timing/knock variables to defaults
            ;-----------------------------------------
            ldd     #$ffa0                  ;                               
            staa    TcasLast0               ;                                  
            staa    knockTimer              ;                                   
            stab    tim61Tot0               ;                                  
            ldaa    t_enerLen               ;                                  
            staa    enerLen                 ;                                

            ;-----------------------------------------
            ; Init air count variables to default 
            ;-----------------------------------------
            ldab    t_airCntMax             ; b = t_airCntMax(0)                              
            stab    airCntMax               ;                                  
            ldaa    #$08                    ;                             
            mul                             ; d = 8 * airCntMax                            
            std     airCnt0                 ;                                
            std     oldAirCnt0              ;                                   

            ;-----------------------------------------
            ; Init engine state flags to notRotating
            ;-----------------------------------------
            ldaa    #$10                    ;                             
            staa    state3                  ; engine notRotating                               
            staa    state1                  ; engine notRotating 

            ;---------------------------------------------
            ; Init cas flags, current cylinder to default
            ;---------------------------------------------
            ldd     #$0503                  ;                               
            staa    tdcCasFlags             ; Why not use std??? I guess it is not obvious taht they are not contiguous just by looking at variable names...                             
            stab    casCylIndex             ;                              

            ;----------------------
            ; More init to default
            ;----------------------
            ldaa    #$ff                    ;                             
            staa    obdInjCmd               ; No obd injector command                                  
            staa    coilChkCnt              ;                                   
            staa    T2_EcuPower             ;                                    
            staa    vss                     ; speed = 0                           

            ;-----------------------------------------------------
            ; Init reed switch flag to current reed switch value
            ; and init 40Hz bit to 1
            ;-----------------------------------------------------
            ldaa    port1                   ;                              
            anda    #$80                    ; Keep only reed switch bit                             
            inca                            ;                             
            staa    rtiReedFlags            ; Store latest Reed switch in bit 7 and set bit 1 for 40Hz based events

            ;---------------------------------------------
            ; More init to default
            ;---------------------------------------------
            ldaa    #$06                    ; 30ms                             
            staa    T200_cop                ;                                  
            staa    T200_40Hz               ;                                  
            staa    L00ca                   ; Never used in the code??????????????                             

            ;---------------------------------------------
            ; More init to default
            ;---------------------------------------------
            ldaa    tpsRaw                  ;                               
            staa    oldTps2                 ;                              
            ldaa    #$0e                    ;                             
            staa    T40_baro                ;                              
            ldd     #$1450                  ;                               
            staa    T40_2hz                 ;                              
            stab    T40_0p5hz               ;                              

            ;--------------------------------------------------
            ; Reset all iscFlags0 and 
            ; If either min or max isc calibration flag was set
            ; set iscStepCurr = 0 and request max calibration
            ; else set flag indicating max calibration is done???
            ;--------------------------------------------------
            ldaa    #$40                    ; Assume max calibration flag is set                             
            brclr   iscFlags0, #$a0, L1007  ; branch if both max and min calibration flags are clear (1010 0000)
            clra                            ;                             
            jsr     iscStepComp             ; iscStepCurr = $00, iscStepCom = (~$00 & 7F) 
            ldaa    #$80                    ;                             
L1007       staa    iscFlags0               ; iscFlags0 = $40 or $80

            ;--------------
            ; Init timer
            ;--------------
            ldaa    #$05                    ;                             
            staa    T40_noPower             ;                                    

            ;------------------------------------------
            ; Init TDC and injector testing valriables
            ;------------------------------------------
            ldab    #$08                    ; b = 0000 1000                            
            stab    tdcCheck                ; tdcCheck = 0000 1000                            
            stab    injToTest               ; injToTest = 0000 1000                              

            ;----------------------------------------------------------------------
            ; Load the ECU configuration variables according to resistor strapping
            ;----------------------------------------------------------------------
            jsr     loadConfig              ;                              

            ;----------------------
            ; re-enable interrupts
            ;----------------------
            cli                             ;
                                      
            ;-----------------------
            ; More init to defaults
            ;-----------------------
            clrb                            ;                             
            stab    T40_mas                 ;                                 
            stab    T40_engRot              ;                                   

            ;-------------------------------------
            ; Init Tcas and TcasOld to max value 
            ; since engine is not rotating
            ;-------------------------------------
            bsr     init_Tcas               ;                              
            rts                                                          
            
            

;******************************************************************
;
; Initialize timer 1 and 2
;
;
;
;******************************************************************
init_t1_t2  orm     t1_csr, #$09             ; Deactivate injector 1 and enable injector 1 output compare interrupts
            orm     t2_csr, #$3d             ; Deactivate injector 3,2,4 and enable injector 3,2,4 output compare interrupts

            ;---------------------------------------------------
            ; Schedule interrupt in 11us for t1 and t2
            ; i.e. Make sure injectors are actually deactivated
            ;---------------------------------------------------
            ldd     t1t2_clk                                                 
            addd    #$000b                                                 
            std     t1_outCmpWr                                                 
            std     t2_outCmpWr                                                 
            rts                                                          



;******************************************************************
;
; Initialize Tcas and TcasOld to $7fff (infinite, not rotating...)
;
;
;
;******************************************************************
init_Tcas   ldx     #Tcas                                                 
            ldd     #$7fff                                                 
            std     $00,x                                                 
            std     $02,x                                                 
            rts                                                          



;******************************************************************
;
;
; First subroutine
;
;
;******************************************************************
            ;----------------------------------------------
            ; Clear counter state flag and check if 40Hz
            ; flag was set by real time interrupt
            ;----------------------------------------------
subroutine1 clra                              ; a=0, used to accumulate various conditions in code below                             
            brclr   rtiReedFlags, #$01, L1013 ; Branch if 40Hz flag is not yet set (flag is set at ~40Hz in RT interrupt)
            andm    rtiReedFlags, #$fe        ; Reset bit
            
            ;---------------------------------------------------------------
            ; 40Hz flag is set, process it (code executed 40 times a second,
            ; at the most...)
            ;---------------------------------------------------------------
            ;---------------------------------------------------------------
            ; Decrement all 40Hz timers (min of 0) from $0117 to $0132
            ;---------------------------------------------------------------
            ldx     #T40_2hz                ;                               
            ldab    #$1c                    ;                             
            jsr     decTable                ;                                 
            inca                            ; a.0=1, set at 40Hz 

            ;------------------------------------------
            ; Update 10Hz flag based on T40_2hz 
            ;------------------------------------------
            ldab    T40_2hz                 ; 
            bitb    #$03                    ;                              
            bne     L1011                   ; Branch 3 times out of 4???
            oraa    #$02                    ; a.1=1, set at ~10Hz

            ;----------------------------------------------------------
            ; Check T40_2hz, loops at $14 (20d), which produces 2Hz
            ;----------------------------------------------------------
L1011       tstb                            ;                             
            bne     L1012                   ; Branch if T40_2hz is not null yet (takes ~0.5sec)

            ;----------------------------------------------------------------------
            ; Decrement all 2Hz timers (min of 0) from $0134 to $13f
            ;----------------------------------------------------------------------
            ldx     #T2_crank               ;                                  
            ldab    #$0c                    ;                             
            jsr     decTable                ;                                 
            oraa    #$04                    ; a.2=1, set at 2Hz 

            ;-----------------
            ; Re-init counter
            ;-----------------
            ldab    #$14                    ;                             
            stab    T40_2hz                 ;
                                            ;                 
            ;---------------------------------------------------------
            ; Check T40_0p5hz, loops at $50 (80d), which produces 0.5Hz
            ;---------------------------------------------------------
L1012       ldab    T40_0p5hz               ;                              
            bne     L1013                   ; Branch if T40_0p5hz is not null yet (takes ~2sec)                           

            ;----------------------------------------------------------------
            ; Decrement all 0.5Hz timers (stop at 0) from $140 to $145
            ;----------------------------------------------------------------
            ldx     #T0p5_crank1            ;                                
            ldab    #$05                    ;                             
            jsr     decTable                ;                                 
            oraa    #$08                    ; a.3=1

            ;-----------------
            ; Re-init counter
            ;-----------------
            ldab    #$50                    ;                             
            stab    T40_0p5hz               ; Re-init T40_0p5hz with $50 (2sec)
            
            ;--------------------------------------------------------
            ; At this point, accum. A contains state of counters updated
            ; in the above code, store it in Tclocks                               
            ;--------------------------------------------------------
L1013       staa    Tclocks                                                 

            ;----------------------------------------------------------------------
            ; Re-init T40_crank, T2_crank, T0p5_crank1 to max if startingToCrank  
            ;----------------------------------------------------------------------
            ldaa    #$ff                    ; a = $ff                             
            brclr   state1, #$01, L1014     ; Branch if startingToCrank is clear
            staa    T40_crank               ; Engine startingToCrank, reset a few timers
            staa    T2_crank                ; 
            staa    T0p5_crank1             ;                               

            ;----------------------------------
            ; Re-init T40_start if key is in start
            ;----------------------------------
L1014       brset   port3Snap0, #$40, L1015 ; Branch if key is not in start
            staa    T40_start               ; Key in start, re-init counter                             

            ;-------------------------------------------------------------------
            ; Load config1 and config2 memories depending on config resistors
            ;-------------------------------------------------------------------
L1015       jsr     loadConfig                   

            ;-------------------------------------------------------
            ; Reset counter T200_cop to $0a (on every loop,
            ; will reach 0 only if main loop takes more
            ; than 50ms=10/200Hz, i.e. main loop slower than 20Hz)
            ; Could be used as a COP monitor to reset ECU???
            ;-------------------------------------------------------
            ldaa    #$0a                    ; 50ms or 20Hz                             
            staa    T200_cop                ; Re-init counter                               
            jsr     initFunc1               ; Re-init ports and other stuff on every loop???, maybe used in conjunction with T200_cop timer...??? 

            ;----------------------------------------
            ; Re-init timer 1 and 2 and t3_csr0 
            ;----------------------------------------
            sei                             ;                             
            andm    t1_csr, #$1b            ;                                 
            orm     t1_csr, #$18            ;                                 
            orm     t2_csr, #$18            ;                                 
            andm    t3_csr0, #$5e           ;                                
            orm     t3_csr0, #$42           ;                                
            cli

            ;---------------------------------------------------------
            ; Re-init some stuff in case the engine is not rotating
            ;---------------------------------------------------------
            sei                             ;                             
            ldab    T40_engRot              ;                                     
            bne     L1016                   ; Branch if T40_engRot not expired                             
            ldd     #$0503                  ; T40_engRot reached 0, re-init stuff since engine not rotating
            staa    tdcCasFlags             ;                              
            stab    casCylIndex             ; Why not std?                             
            clr     injPw                   ;                              
            jsr     init_t1_t2              ;                         
                 
            ;---------------------------------------------------------
            ; Re-init cas related controls if T40s_casInt is expired 
            ; i.e. no CAS interrupts received for over 1.275sec
            ;---------------------------------------------------------
L1016       brset   T40s_casInt, #$ff, L1017 ; Branch if T40s_casInt not expired (not 0)                               
            clr     tdcCasCount              ; tdcCasCount = 0                                    
            orm     t3_csr0, #$0c            ; set 0000 1111, disable both power transistor coils and ???
            orm     t3_csr1, #$0a            ; set 0000 1010,                                                                   
            clra                             ;                                                                   
            staa    enerFlags                ;                                                                    
L1017       cli                              ;                                                                 

            ;------------------------------
            ; Check if ECU is in test mode
            ;------------------------------
            brset   port4, #$08, L1018       ; Branch if ECU test mode terminal is grounded

            ;--------------------------------------
            ; Not in test mode, Reset serial comm.
            ;--------------------------------------
            ldd     sci_scr                          ; Read serial port at address 0011 (status) and 0012 (data) (clears it)?       
            ldd     #($0400 |((baudRate & $03)<<8))  ; A=06, B=00                                                                    
            std     sci_baud                         ; set serial port mode, sci_rate=06, sci_cr=00                                                          
            orm     obdInjCmd, #$3f                  ; Reset all injector off commands                                                                         
            clr     obdActCmd                        ; Reset all actuator on commands
            andm    obdFlags, #$3c                   ; Reset stored serial port state to 00xxxx00?, FA.0 and FA.1 are reset to 0                                  
            bra     L1022                                                      
            
            ;------------------------------------
            ; At this point, we are in test mode
            ;------------------------------------
L1018       brset   obdFlags, #$02, L1019     ; Check if port2.4 initialized to 1 (output to serial connector)?                                                 
            orm     port2, #$10               ; Set output to serial port to 1 (heart beat level on diagnostic port if TE not enabled)                          
            orm     obdFlags, #$02            ; Set $FA.1 indicating we initialized default serial port output                                                   
L1019       brset   obdFlags, #$01, L1020     ; branch if FA.0 is 1? (FA.0 seems to be toggled on every loop)                                                   

            ;---------------------------------------------------------------------------------
            ; At this point serial tx was previously enabled, reset all parameters anyway
            ; Code is executed only after tx is enabled on first loop (preamble is sent, 
            ; we don't want to receive the echo...) and then at 1/2 loop frequency
            ;---------------------------------------------------------------------------------
            ldaa    #($04 | (baudRate & $03)) ;
            ldab    sci_scr                   ;                              
            andb    #$fa                      ;                           
            orab    #$18                      ;                           
            std     sci_baud                  ; Set baud rate and serial port mode                               
            orm     obdFlags, #$01            ;                                 
            bra     L1021                     ;                            
L1020       orm     sci_scr, #$02             ;                                
            andm    obdFlags, #$fe            ;                                 
L1021       clr     errCodeProc               ; Reset code (no code...) being output to test connector (heart beat mode)                                    

            ;------------------------------------------------
            ; Build port3Snap0 from port3
            ;------------------------------------------------
L1022       ldaa    port3                   ; a = port3                              
            anda    #$fb                    ; Reset 0000 0100
#ifdef E932
            ldab    T40_start               ;                              
            addb    #$3c                    ; add 1.5s                            
            bcc     L1023                   ; branch if key was out of start for more than than 1.5s                            
#endif
            oraa    #$20                    ; force setting of park/neutral flag                             
L1023       ldab    T40_crank               ;                                   
            addb    #$ac                    ; 4.3s                             
            bcc     L1024                   ; branch if engine stopped "startingToCrank" more than 4.3s ago                              
            oraa    #$10                    ; Force setting of A/C switch flag                             
L1024       brclr   state1, #$11, L1025     ; Branch if both notRotating and startingToCrank clear
            oraa    #$30                    ; engine is either notRotating or startingToCrank, force setting of both A/C switch  and park/neutral flags                              
L1025       ldab    ectFiltered             ;                              
            cmpb    #$9b                    ; 10.2degC                              
            bcs     L1026                   ; Branch if ECT temperature lower than threshold                             
            anda    #$f7                    ; Reset $08, power steering flag                            
L1026       staa    port3Snap0               ;                              

            ;----------------------------
            ; Build port4Snap from port4
            ;----------------------------
            ldaa    port4                   ;                              
            anda    #$78                    ; Only keep 01111000                             
            staa    port4Snap               ;                              

            ;------------------------------------------
            ; Read some ADC inputs 
            ;     ECT (engine coolant temp)
            ;     IAT (intake air temp)
            ;     BARO
            ;     O2
            ;     EGRT
            ;------------------------------------------
            ldy     #$00cb                  ;                               
            ldaa    #$08                    ;                             
L1027       psha                            ;                             
            jsr     readAdc1                ;                                 
            cli                             ;                             
            stab    $00,y                   ; y = y + 1                              
            pula                            ;                             
            inca                            ;                             
            cmpa    #$0d                    ;                             
            bcs     L1027                   ;       
                                   
            ;------------------------------------------------------
            ; Validate and condition raw engine coolant temperature
            ;------------------------------------------------------
            andm    state2, #$f0            ; Reset error flags before update below                                 
            ldab    ectRaw                  ; b = ectRaw                              
            cmpb    #$05                    ; 141degC                            
            bcs     L1028                   ;                              
            cmpb    #$ec                    ; -52degC                             
            bls     L1029                   ;                              
L1028       ldab    #$1e                    ; Use default of 83degC
            orm     state2, #$01            ; Set error flag                                

            ;-------------------------------------------------
            ; Check some conditions for filtered ECT update
            ;-------------------------------------------------
L1029       brclr   state2, #$10, L1030     ;                                
            ldab    #$1e                    ; Use default of 83degC
L1030       brset   state1, #$10, L1033     ; Branch if notRotating                                
            brclr   Tclocks, #$04, L1035    ; Branch if 2Hz signal not set

            ;----------------------------------------------------
            ; At this point 2 Hz signal is set and  b = validated ECT
            ;
            ; Filter the validated ECT
            ;
            ; This section of code computes ectFiltered which
            ; is basically the same as validated ECT except
            ; that it can only increase by 3 units every 0.5s...
            ; or decrease by 1 unit every 0.5s
            ;----------------------------------------------------
            ldaa    ectFiltered             ; a = ectFiltered
            sba                             ; a = a-b = ectFiltered - validated ECT = ECTdiff
            bcc     L1031                   ; Branch if ectFiltered >= validated ECT (new temp is higher than old one, which is normal case when warming...)
            ldab    ectFiltered             ; ectFiltered < validated ECT (temperatured lowered...)                             
            cmpb    #$54                    ; 41degC                             
            beq     L1034                   ; branch if equal to this temp????                            
            incb                            ; else increment validated ECT (decrease temp) by 1 at a time (slowly change it to reflect sensor value...)
            bra     L1033                   ;

L1031       cmpa    #$03                    ; Check ECT difference
            bls     L1032                   ; Branch if ECT difference <= 3  (5F)                             
            ldaa    #$03                    ; Difference higher than 3, use 3                            
L1032       suba    ectFiltered             ;                              
            nega                            ; a = ectFiltered-min(ECTdiff,3) =  ectFiltered - min(ectFiltered-validatedECT, 3) = validatedECT if difference smaller than 3, else it lags behind... 
            tab                             ; b = ectFiltered-min(ECTdiff,3)

L1033       ldaa    #$96                    ; 300s (5 minutes!!!)                              
            staa    T0p5_ect                ; Reset counter                               
L1034       stab    ectFiltered             ; ectFiltered = filtered and validated ECT

            ;----------------------------------------------------------
            ; Compute ectCond which is used for table interpolation
            ; Limit max value to $e0 (min temp of -29degC) 
            ; Scale by 8 below $20 (temp above 80degC) 
            ;
            ;     ectFiltered          ectFiltered        ectCond
            ;  -31degC to -59degC          $e1-$ff   ->   $e0        
            ;   80degC to -29degC          $20-$e0   ->   $20-$e0    
            ;   81.3degC                       $1f   ->   $18        
            ;   82.8degC                       $1e   ->   $10        
            ;   84.3degC                       $1d   ->   $08        
            ;   158degC to 85.9degC        $00-$1c   ->   $00        
            ;----------------------------------------------------------
L1035       ldab    ectFiltered             ;                                    
            cmpb    #$e0                    ; -29degC                            
            bls     L1036                   ; Branch if ectFiltered <= $e0
            ldab    #$e0                    ; Use max of $e0
L1036       cmpb    #$20                    ; 80degC  
            bcc     L1038                   ; Branch if ectFiltered >= $20
            subb    #$1c                    ; b = ectFiltered - $1c
            bcc     L1037                   ; Branch if no underflow
            clrb                            ; underflow, use 0 
L1037       aslb                            ;                             
            aslb                            ;                             
            aslb                            ; b = (ectFiltered-$1c)*8 
L1038       stab    ectCond                 ; Store conditionned ect          
                     
            ;-------------------------------------------------
            ; Validate/condition raw intake air temperature
            ;-------------------------------------------------
            ldab    iatRaw                  ;                               
            cmpb    #$0e                    ; 122degC
            bcs     L1039                   ; Branch if temp > 122degC
            cmpb    #$ea                    ; -49degC                            
            bls     L1040                   ; Branch if temp > -49degC                              
L1039       orm     state2, #$02            ; Set fault code                                
            ldab    #$7b                    ; Use 25degC
L1040       stab    iatChecked              ;                 
             
            ;-----------------------------------------------------------
            ; Compute conditionned IAT for later table interpolation
            ;-----------------------------------------------------------
            ldx     #$e020                  ; Load x with max/offset (max=$e0)                              
            jsr     clipOffset              ; b = max(min(b,$e0)-$20,0)-> offset and clip temp, returns b=$00 to $c0
            stab    iatCond                 ; Conditionned IAT
                                         
            ;-------------------------------------------------
            ; Compute air density factor based on air temperature
            ;-------------------------------------------------
            ldx     #t_airDens              ;                               
            jsr     iatCInterp              ;                              
            stab    iatCompFact             ; Air density factor                             

            ;---------------------------------------------------
            ; Check battery voltage for baro sensor validation
            ;---------------------------------------------------
            ldaa    battRaw                   ;                                 
            cmpa    #$6d                      ; 8V
            bcc     L1042                     ; Branch if more than 8V                             
            ldaa    #$0e                      ; battery voltage too low, start timer??? (0.35sec)                            
            staa    T40_baro                  ;                              

            ;------------------------------------------------------------
            ; Validate baro range, T40_baro is used to ignore baroRaw
            ; When battery<8v (and 0.35s after it is >8V)
            ;------------------------------------------------------------
L1042       ldab    baroRaw                   ; 
            ldaa    T40_baro                  ;                                                                 
            bne     L1044                     ; Branch if battery voltage was too low                                                                
            cmpb    #$e4                      ; 1.1 bar                                                       
            bcc     L1043                     ; branch if baroRaw > 1.1
            cmpb    #$64                      ; .49 bar                                                       
            bcc     L1045                     ; branch if baroRaw > .49
L1043       orm     state2, #$04              ; Set error flag
L1044       ldab    #$cd                      ; Use 1.0 bar                                           
L1045       stab    baroChecked               ;                                                                

            ;-----------------------------------------------------
            ; Compute conditionned baro for table interpolation
            ;-----------------------------------------------------
            ldx     #$bd5d                    ;                                                                  
            jsr     clipOffset                ; b = max(min(b,$bd)-$5d,0)-> offset and clip baro, returns b = $00 to $60  (0.45bar to 0.92bar???)                                           
            cmpb    #$40                      ;                                                                
            bcs     L1046                     ; branch if b < $40 
            aslb                              ; else mult by 2                                                
            subb    #$40                      ; and sub 40 -> 1:1 scale for $00 to $40 and 2:1 scale for $40 to $60, new max is $80, not $60                                                   
L1046       stab    baroCond                  ; Conditionned baro used in table lookup

            ;----------------------------------------------------
            ; Compute barometric pressure factor for fuel inj.
            ;----------------------------------------------------
            ldab    baroChecked               ;                                                 
            ldaa    #$a0                      ;                                                                
            mul                               ; baroChecked*160                                                              
            aslb                              ;                                                                
            adca    #$00                      ; round-up                                                              
            staa    baroFact                  ; barometric pressure factor = rounded baroChecked*160/256 -> pressure is (baroFact/128) bar, i.e. $80 = 1 bar                                                    

            ;-------------------------------------------------------------
            ; Transfer tpsDiffMax1 to tpsDiffMax2 and reset tpsDiffMax1 
            ;-------------------------------------------------------------
            sei                               ;                                                              
            ldaa    tpsDiffMax1               ;                                  
            clr     tpsDiffMax1               ;                                  
            cli                               ;                           
            staa    tpsDiffMax2               ;     
                                         
            ;-----------------------------------------------------------
            ; If engine is not rotating, re-init Tcas and use rpm = 0
            ;-----------------------------------------------------------
            brclr   state1, #$10, L1047       ; Branch if notRotating clear
            jsr     init_Tcas                 ; engine is notRotating, re-init Tcas
            clra                              ;                              
            clrb                              ; use d = rpm = 0 for below                             
            bra     L1048                     ;                              

            ;------------------------------------------------------------------------
            ; Update rpm variables from Tcas (Tcas is obtained from CAS interrupt)
            ;------------------------------------------------------------------------
L1047       ldd     Tcas                      ;                               
            jsr     calcFreq                  ; D = $EA600/Tcas = 960000/Tcas = 960000/(125000/2/(rpm/60)) = 0.256*rpm                                
L1048       std     rpm4                      ; RPM4 = #$EA600/Tcas = 0.256*rpm                                                                    
            jsr     scale2m                   ; scale D by 2                                                                                           
            stab    rpm8                      ; rpm8 = #$EA600/Tcas/2 = rpm/7.8125                                                              
            ldd     rpm4                      ; D = #$EA600/Tcas                                                                                     
            jsr     scale8m                   ; D = #$EA600/Tcas/8 = rpm/31.25                                                                       
            stab    rpm31                     ; rpm31 = #$EA600/Tcas/8 = #$EA600 / (125000/2/(rpm/60)) / 8 = rpm/31.25.                              

            ;------------------------------------------------------
            ; Compute rpmIndex1 for eventual map interpolation 
            ;------------------------------------------------------
            ldaa    #$90                      ; a=$90 (4500rpm)                            
            jsr     rpmRange                  ; get rpm for map interpolation, b = min(max(RPM31p25-#$10, 0), $90) = min(max(RPM31p25-500rpm,0),4500rpm)  
            stab    rpmIndex1                 ; rpmIndex1
                                         
            ;-------------------------------------------------------------
            ; if notRotating or startingToCrank. Use rpmX4Filt = 16*rpm4
            ;-------------------------------------------------------------
            brclr   state1, #$11, L1049       ; branch if notRotating and startingToCrank clear 
            ldd     rpm4                      ; engine is either notRotating or startingToCrank                               
            asld                              ;                             
            asld                              ;                             
            asld                              ;                             
            asld                              ; d = 16*rpm4                              
            andm    masCasFlags, #$fe         ; reset masCasFlags.1                                
            bra     L1050                     ; 
                                         
            ;-----------------------------------------------------------------
            ; Engine is running, Use rpmX4Filt = filtered(16*rpm4)
            ; Update only when masCasFlags.1 was set by interrupt 
            ;
            ; rpmX4Filt is basically the filtered version of rpm4 where 
            ; an exponential averaging filter is used
            ;
            ; rpmX4Filt = $e8/256 * oldrpmX4Filt + $18/256   * 16*rpm4
            ;              alpha * oldrpmX4Filt + (1-alpha) * 16*rpm4
            ;
            ; where alpha = 0.90625
            ;-----------------------------------------------------------------
L1049       brclr   masCasFlags, #$01, L1051  ; Branch if flag not set                              
            andm    masCasFlags, #$fe         ; Reset the flag
            ldx     rpmX4Filt                 ; x = rpmX4Filt                             
            ldab    #$e8                      ; b = $e8                            
            jsr     mul816b                   ; d = $e8/256 * rpmX4Filt, temp3 = lower 8 bits of result                                 
            std     rpmX4Filt                 ; rpmX4Filt = $e8/256 * rpmX4Filt                             
            ldaa    temp3                     ; 
            staa    temp4                     ; temp4 = temp3 = lower 8 bits of ($e8/256 * old rpmX4Filt)                              
            ldd     rpm4                      ;                             
            asld                              ;                             
            asld                              ;                             
            asld                              ;                             
            asld                              ; d = 16 * rpm4                            
            xgdx                              ; x = 16 * rpm4                             
            ldab    #$e8                      ; b = $e8                            
            negb                              ; b = -$e8 = $18 (why not load it directly, maybe mitsu compiler stuff...?)                            
            jsr     mul816b                   ; d = $18/256 * 16 * rpm4                                
            xgdx                              ; x = $18/256 * 16 * rpm4                             
            clrb                              ; b = 0                            
            ldaa    temp3                     ; a = lower 8 bits of ($18/256 * 16 * rpm4)                              
            adda    temp4                     ; a = lower 8 bits of ($18/256 * 16 * rpm4) + lower 8 bits of ($e8/256 * old rpmX4Filt)                             
            rolb                              ; b = carry bit (if a carry was generated) from that addition                             
            rola                              ; a = a*2 (shift upper bit for roundoff purposes)                           
            adcb    #$00                      ; Round off. At this point, b contains the rounded-up highest bit of the addition of the lowest 8 bits
            abx                               ; x = $18/256 * 16 * rpm4 + rounded lower 1 bit                                                                               
            xgdx                              ; d = $18/256 * 16 * rpm4 + rounded lower 1 bit                                                                                 
            addd    rpmX4Filt                 ; d = $18/256 * 16 * rpm4 + $e8/256 * old rpmX4Filt                                                                                   
L1050       std     rpmX4Filt                 ; Store new value                            
                                                   
            ;-------------------------------------------------------------
            ; Restart T40_mas if engine notRotating or startingToCrank 
            ;-------------------------------------------------------------
L1051       brclr   state1, #$11, L1052       ; branch if notRotating and startingToCrank clear
            ldaa    #$0c                      ; Engine is either notRotating or startingToCrank                                                                              
            staa    T40_mas                   ; Restart timer at 0.3s 

            ;-----------------------------------------
            ; Set state2 mas flag if T40_mas expired
            ;-----------------------------------------
L1052       ldaa    T40_mas                   ; 
            bne     L1053                     ; Branch if counter not yet 0                                                                               
            orm     state2, #$08              ; Set bit indicating timer expired

            ;---------------------------------------------------------------------------
            ; Compute mafRaw16 and mafRaw from airCnt0:airCnt1 
            ;
            ; Since airCnt0:airCnt1 is filtered airCntNew0:airCntNew1, we have
            ;
            ;   mafRaw = $200d * airCnt0 / Tcas / 64  
            ;          = 8205 * airCntNew0 / Tcas / 64          
            ;          = 8205 * (N+r) * $9c / Tcas / 64        (see airCntNew0 definition)
            ;          = 8205 * (N+r) * $9c / (125000*TcasInSeconds) / 64
            ;          = (N+r)/TcasInSeconds/6.25
            ;          = "number of airflow sensor pulse per sec" / 6.25
            ;
            ; Where:
            ; 
            ;     -Tcas is the time required for 1 cas interrupt (there are 4 cas 
            ;      interrupts for every 2 rotations which basically means 1 cas 
            ;      interrupt for every complete cycle of one cylinder)
            ;     -(N+r) is the number of air sensor pulses received during
            ;            one cas interrupt, r<1 is the fractional part. See
            ;            the mas interrupt for assumptions...
            ;     -Tcas is the cas interrupt period measured at 125KHz 
            ;
            ;---------------------------------------------------------------------------
L1053       ldd     Tcas                      ; d = Tcas                                                                                        
            std     temp4                     ;                                                                                       
            ldd     #$200d                    ; d = $200d = 8205d                                                                                      
            ldx     airCnt0                   ;                                                                                          
            stx     temp6                     ;                                                                                       
            jsr     mul1616                   ; d = d * temp6:temp7 = ($200d * airCnt0)/65536 = 0.125198*airCnt0
            jsr     div3216                   ; d = 65536*0.125198*airCnt0/Tcas = 8205 * airCnt0/Tcas                                                                  
            std     mafRaw16                  ; 16 bit mafRaw                                                                                      
#ifdef masLog2X                               ;                        
            jsr     scale128m                 ;                                              
#else                                         ;            
            jsr     scale64m                  ; d = 8205*airCnt0/Tcas/64, result is in B...                                 
#endif                                        
            brset   state1, #$10, L1054       ; Branch if engine notRotating
            brclr   state2, #$08, L1055       ; Branch if pulse accumulator interrupts received
L1054       clrb                              ; No interrupts or notRotating, use 0 air flow                            
L1055       stab    mafRaw                    ; Store 8 bit mafRaw =  8205*airCnt0/Tcas/64

            ;----------------------------------------------------------------------
            ; Compute airCntMax (max air count as a function of rpm, ect and iat)
            ;----------------------------------------------------------------------
            ldd     rpm4                      ; d = rpm4                                                                       
            cmpa    #$03                      ; compare high part to 3 -> compare D to 768                                       
            bcs     L1057                     ; Branch if RPM < 3000                                                              
            ldd     #$0300                    ; RPM >=3000 -> use 3000                                                             
L1057       asld                              ;                                                                                  
            asld                              ; scale rpm
            ldx     #t_airCntMax              ;                                                                                   
            jsr     interp1                   ; b = t_airCntMax[rpm]
            clra                              ;                                                                                  
            std     temp6                     ; temp6:temp7 = t_airCntMax[rpm]
            ldx     #L1990                    ;                               
            ldaa    ectCond                   ;                                
            jsr     interp32mul               ; D = t_airCntMax[rpm] * L1990[ectCond]
            ldx     #L1991                    ;                               
            ldaa    iatCond                   ;                                
            jsr     interp32mul               ; D = t_airCntMax[rpm] * L1990[ectCond] * L1991[iatCond]
            jsr     ovfCheck                  ; Check for overflow                              
            stab    airCntMax                 ; airCntMax = t_airCntMax[rpm] * L1990[ectCond] * L1991[iatCond]
                                          
            ;------------------------------------------------
            ; Store airCntMax in airCnt0 and oldAirCnt0 
            ; when engine is notRotating or startingToCrank
            ;------------------------------------------------
            brclr   state1, #$11, L1060       ; branch if notRotating and startingToCrank clear   
            clra                              ; engine is either notRotating or startingToCrank                                
            asld                              ;                           
            asld                              ;                           
            asld                              ; d = airCntMax*8                             
            std     airCnt0                   ; airCnt0:airCnt1 = airCntMax*8                                 
            std     oldAirCnt0                ; oldAirCnt0 = airCntMax*8                              

            ;----------------------------------------------
            ; Compute airCntDef, default airCnt0 value 
            ; when no mas interrupts are being received 
            ;----------------------------------------------
L1060       ldy     #L2053                    ;                               
            jsr     rpmPwise                  ; b = F(rpm4), see L2053 table                                
            pshb                              ;                             
            ldx     #L2036                    ;                               
            jsr     interpEct                 ;                                  
            addb    tpsRaw                    ; b = tpsRaw + L2036[ect]                            
            bcc     L1062                     ; overflow check                              
            ldab    #$ff                      ; Use max                            
L1062       ldx     #$ba1a                    ;                               
            jsr     clipOffset                ; offset and clip b, b = max(min(tpsRaw + L2036[ect],$ba)-$1a,0)
            lsrb                              ; b = b/2                           
            pula                              ; a = F(rpm4)                            
            ldx     #L1986                    ;                               
            ldy     #$0500                    ;                               
            jsr     lookup2D2                 ; b = L1986[a,b], 2D interpolated air count since stored in airCntDef which is stored in airCnt0 under some cases??? 
            ldaa    #$57                      ;                             
            mul                               ; b = $57*L1986[a,b]                            
            jsr     scale128m                 ; b = $57*L1986[a,b]/128                                 
            stab    airCntDef                 ; airCntDef = $57*L1986[a,b]/128                             
            
            ;------------------------------------------------------
            ; Re-init airFiltFact (airflow filtering factor)
            ;
            ; Filtering factor depends on current conditions???
            ;------------------------------------------------------
#ifdef E931
            ldaa    #$b3                       ; Value to use if timer T40_ftrim2 is expired                             
            ldab    T40_ftrim2                 ;                               
            beq     L1064                      ;                               
#endif                                         
            ldaa    #$d1                       ;                             
            brset   iscLrnFlags, #$10, L1064   ; Branch if conditions are good to update isc variables                              
            ldaa    #$e4                       ;                             
L1064       staa    airFiltFact             

            ;-------------------------------------------------------------
            ; Transfer airDiffPos:airDiffNeg to airDiffPos1:airDiffNeg1
            ; and re-init airDiffPos:airDiffNeg to 0                                    
            ;-------------------------------------------------------------
            clra                              ;                             
            clrb                              ;                             
            sei                               ;
            ldx     airDiffPos                ;                                   
            std     airDiffPos                ;                                   
            cli                               ;                             
            stx     airDiffPos1               ;                              

            ;-----------------------------------------------------------------------------------------
            ; Compute airCntMin0 (minimum value of airCntNew0 before it is used for airCnt0 calc)
            ;-----------------------------------------------------------------------------------------
            clra                            ;                             
            clrb                            ; d = 0                            
            brset   state1, #$11, L1065     ; branch if engine notRotating or startingToCrank (use minimum of 0)
            ldaa    #$10                    ;                               
#ifdef E931
            ldab    #$81                                                 
#else
            ldab    #$91                                                 
#endif
            mul                             ;                            
            ldx     Tcas                    ;                               
            stx     temp6                   ;                              
            jsr     mul1616                 ;                                
            ldx     #$4000                  ;                               
            stx     temp6                   ;                              
            jsr     mul1616                 ;                                
            xgdx                            ;
#ifdef E931
            ldab    baroFact                ;                                 
#else
            ldab    #$80                    ; Use 1.0 bar
            nop                                                          
#endif
            ldaa    iatCompFact             ;                                    
            mul                             ;                             
            std     temp4                   ;                              
            xgdx                            ;                             
            jsr     div3216                 ;                                
L1065       std     airCntMin0              ; Store "min" used in air count calc                              

            ;---------------------------------------------------------------
            ; Compute airVol16 and airVol from [airCnt0:airCnt1]*masScalar
            ;---------------------------------------------------------------
            clra                            ;                             
            clrb                            ;                             
            brset   state1, #$10, L1066     ; Branch if engine notRotating                                
            ldd     #masScalar              ; 16 bit MAS scalar ($5e86 for 1G, $7A03 for 2g), seem to correspond to (masComp+t_mascomp(72Hz))/512*65536   
            std     temp6                   ; Store for 16 multi.                                               
            ldd     airCnt0                 ; MAS air count                                                          
            jsr     mul1616                 ; d = masScalar/65536 * [airCnt0:airCnt1]
L1066       std     temp6                   ; temp6:temp7 = masScalar/65536 * [airCnt0:airCnt1]
            std     airVol16                ; airVol16 = masScalar/65536 * [airCnt0:airCnt1]
            jsr     scale2m                 ; b = masScalar/65536 * airCnt0 / 2 with overflow check
            stab    airVol                  ; airVol = masScalar/65536*[airCnt0:airCnt1]/2 (8 bit airflow)                                                     

            ;--------------------
            ; Compute airVolCond 
            ;--------------------
            tba                             ; a = airVol                             
            jsr     L1647                   ; b = Apply offset and scaling to airVol???                              
            stab    airVolCond              ;                              

            ;----------------------------------------
            ; At this point [temp6:temp7] = airVol16  
            ;
            ; Compute airVolT, airVolTB and airVolB
            ;----------------------------------------
            ldab    iatCompFact             ;                                    
            jsr     mul816_256              ; b = airVol16/2 * iatCompFact/128; [temp6:temp7] = airVol16 * iatCompFact/128
            stab    airVolT                 ; airVolT =  airVol16/2 * iatCompFact/128
            jsr     mul816_baro             ;  
            stab    airVolTB                ; airVolTB = airVol16/2 * iatCompFact/128 * baroFact/128; 
            ldd     airVol16                ; d = airVol16                                 
            std     temp6                   ;                              
            jsr     mul816_baro             ;                              
            stab    airVolB                 ; airVolB = airVol16/2 * baroFact/128                               
            
#ifdef E931       
            ;---------------------------------------------------                          
            ; Set ftrimFlags.3 if speed exceed threshold (with
            ; hysteresis) and port3.0 is set?????????
            ;---------------------------------------------------                          
            andm    ftrimFlags, #$f7         ; Assume we reset flag $08, updated below                                 
            ldaa    #$18                     ; speed threshold = $18                            
            brclr    ftrimFlags, #$04, Md4d4 ; branch is flag not yet set                                
            ldaa    #$1c                     ; Flag already set, use higher threshold (lower speed threshold)                             
Md4d4       andm    ftrimFlags, #$fb         ; Assume we reset $04                                 
            cmpa    vss                      ; 
            bcs     L1067                    ; Bail if speed < 24km/h (vss=1/speed...)
            orm     ftrimFlags, #$04         ; speed > 24km/h, set "threshold exceeded" bit
            ldaa    port3Snap0               ; Get stored port3                                  
            anda    port3                    ; Confirm bit is still set with current value                              
            lsra                             ; Get confirmed bit 0 in carry                              
            bcc     L1067                    ; Branch if bit was not set                              
            orm     ftrimFlags, #$08         ; Bit was still set, set flag bit                                 
#endif

            ;-----------------------------------------------
            ; Set ftrimFlags.4 if rpm exceeds 
            ; threshold (around 1000rpm), with hysteresis
            ;-----------------------------------------------
L1067       ldx     #L1983                  ; x points to initial threshold                               
            brclr   ftrimFlags, #$10, L1068 ; Branch if flag not yet set                              
            inx                             ; Flag is set, go to next value (hysteresis)
L1068       .equ    $
#ifdef E932
            brset   port3Snap0, #$20, L1069 ; branch if Park/neutral                               
            inx                             ; even more threshold hysteresis...                            
            inx                             ; even more threshold hysteresis...                            
#endif        
L1069       ldaa    rpm31                   ;                              
            andm    ftrimFlags, #$ef        ; Assume we reset $10                               
            cmpa    $00,x                   ; Compare rpm to treshold
            bcs     L1070                   ; branch if rpm31 < L1983(flags...)                              
            orm     ftrimFlags, #$10        ; set flag indicating we are above rpm threshold                                

            ;----------------------------------------------------------------------------------------
            ; Update the fuel trim range (low, mid, high)  according to mafRaw16. Table 
            ; t_ftrimRg provides the 2 thresholds with some hysteresis (+/-6Hz)
            ; The trim range is stored in L00e3.0.1 (lowest 2 bits)
            ;
            ; old L00e3.0.1    resulting X       new L00e3.0.1
            ;   00              t_ftrimRg        00 if maf < t_ftrimRg(00) otherwise 01
            ;   01              t_ftrimRg        00 if maf < t_ftrimRg(01) otherwise 01 if maf < t_ftrimRg(02) otherwise 10
            ;   10              t_ftrimRg+1      01 if maf < t_ftrimRg(03) otherwise 10 
            ;   11              t_ftrimRg+1      01 if maf < t_ftrimRg(03) otherwise 10 
            ;
            ;  L00e3.0.1        meaning
            ;     00        low trim (below first threshold)
            ;     01        mid trim (between first and second threshold)
            ;     10        high trim (above second threshold)
            ;     11        Never used I think
            ;----------------------------------------------------------------------------------------
L1070       ldx     #t_ftrimRg              ; X pointx to t_ftrimRg min1                                  
            ldd     mafRaw16                ; d = mafRaw16                                
            jsr     scale64m                ; d = mafRaw16/64 (thats equal to mafRaw...?)                                
            tba                             ; a = mafRaw16/64 = mafRaw (6.25x)Hz                            
            clrb                            ; b=0                            
            brclr   ftrimFlags, #$03, L1074 ;                               
            brclr   ftrimFlags, #$02, L1071 ;                               
            inx                             ; X pointx to t_ftrimRg+1
            bra     L1073                   ;                              
L1071       cmpa    $01,x                   ;                              
            bcs     L1077                   ; Branch if mafRaw16/64 < t_ftrimRg                              
L1073       cmpa    $02,x                   ;                             
            bcs     L1076                   ; Branch if mafRaw16/64 < t_ftrimRg                             
            bra     L1075                   ;                              
L1074       cmpa    $00,x                   ;                              
            bcs     L1077                   ; Branch if mafRaw16/64 < t_ftrimRg                             
            bra     L1076                   ;                               
L1075       incb                            ;                             
L1076       incb    
L1077       ldaa    ftrimFlags              ; a = ftrimFlags
            anda    #$fc                    ; Reset trim range 
            aba                             ; Add new trim range                            
            staa    ftrimFlags              ; Update ftrimFlags
        
            ;---------------------------------------------------
            ; Restart timer T40_ftrim2 on E931 if 
            ;
            ;     rpm > 1953rpm 
            ;  or speed > 15 km/h    
            ;  or speed < 2.5 km/h    
            ;  or vss*rpm/15.625 < $cd8   (note speed ~ 1/vss)
            ;  or airVol > $38 
            ;  or tpsDiffMax2 > $04
            ;---------------------------------------------------
#ifdef E931
            ldd     rpm4                    ;                              
            jsr     scale4m                 ;                                 
            cmpb    #$7d                    ; 1953rpm                             
            bcc     Md551                   ; Branch if rpm>1953rpm                              
            ldaa    vss                     ;                             
            cmpa    #$26                    ; ~15km/h                                
            bcs     Md551                   ; Branch if speed>15km/h                                           
            cmpa    #$e2                    ; ~2.5km/h                                 
            bcc     Md551                   ; Branch if speed<2.5km/h                             
            mul                             ;                              
            cmpd    #$0cd8                  ; d = vss*rpm/15.625                               
            bcs     Md551                   ; branch if vss*rpm/15.625 < $cd8                              
            ldaa    airVol                  ;                                
            cmpa    #$38                    ;                              
            bcc     Md551                   ; Branch if airVol > $38                              
            ldaa    tpsDiffMax2             ;                                     
            cmpa    #$04                    ;                              
            bcs     L1078                   ; Branch if tpsDiffMax2 < $04                              
Md551       ldaa    #$78                    ; 3 sec                              
            staa    T40_ftrim2              ;                               
#endif        

            ;---------------------------------------------------
            ; Reload T40s_Idle as long as idle switch is off
            ;---------------------------------------------------
L1078       brset   port3Snap0, #$80, L1079 ; Branch if idle position switch on                                
            ldaa    #$1e                    ;                             
            staa    T40s_Idle               ; Reload down counter (~0.75sec)                             

            ;---------------------------------------------------------------------
            ; Check for airVolT threshold with hysteresis and update T2_airVolT
            ; ftrimFlags is set when airVolT > 24 and is reset when airVolT <= 15
            ;---------------------------------------------------------------------
L1079       ldaa    #$0f                    ; Threshold min                            
            brset   ftrimFlags, #$80, L1080 ;                                
            ldaa    #$18                    ; Threshold max
L1080       andm    ftrimFlags, #$7f        ; 
            cmpa    airVolT                 ; Compare current air volume                                
            bcc     L1081                   ; Branch if airVolT <= threshold                              
            orm     ftrimFlags, #$80        ; airVolT > threshold, set bit
            ldaa    #$0a                    ; reset timer to 5 seconds                            
            staa    T2_airVolT              ;                            
L1081       brset   state2, #$08, L1083     ; Branch if no pulse accumulator interrupts received
            brset   state1, #$10, L1083     ; Branch if engine notRotating                               

            ;-----------------------------------------------------------
            ; Compute air volume used in fuel cut comparison
            ; it uses 16 bits since 8 bit air volume saturate at ~1g of air/cas
            ;-----------------------------------------------------------
            ldd     airVol16                ; d = airVol16
            jsr     scale4m                 ; b = airVol16/4 (makes sure it fits in b only...)
#ifdef extLoadRange                         ;
            stab    L0054                   ;                              
#else                                       ;
            stab    temp1                   ; temp1 = airVol16/4
#endif                                      ;
            ldaa    iatCompFact             ; Correct for air temp                              
            mul                             ;                             
            jsr     scale128m               ; d = airVol16/4 * iatCompFact/128 
            ldaa    baroFact                ; a = baroFact
            mul                             ;                             
            jsr     scale128m               ; d = airVol16/4 * iatCompFact/128 * baroFact/128 (fits in b only)

            ;---------------------------------------------------------------------------------------
            ; Keep the minimum of airVol16/4 and airVol16/4 * iatCompFact/128 * baroFact/128 
            ;---------------------------------------------------------------------------------------
#ifdef extLoadRange
            cmpb    L0054                   ;
            bcs     L1082                   ;                              
            ldab    L0054                   ;
#else
            cmpb    temp1                   ;                               
            bcs     L1082                   ; Branch if airVol16/4 * iatCompFact/128 * baroFact/128 <= airVol16/4 
            ldab    temp1                   ; Use max of airVol16/4
#endif

            ;------------------------------------------------------------------------------
            ; Check air volume for eventual fuel cut 
            ; When air volume exceeds a threshold, Timer T40_fuelCut 
            ; is not re-initialized on every loop (to 1s) and therefore starts 
            ; counting down. when it reaches 0, fuel cut is applied, see L1090 below
            ;------------------------------------------------------------------------------
L1082       cmpb    #fuelCutVal             ; Air volume based fuel cut value    $a0 = 1.25g/cas
#ifdef noFuelCut
            brn     L1084                   ;
#else
            bcc     L1084                   ; Branch if air volume>=threshold                
#endif
L1083       ldab    #$28                    ; 1 sec
            stab    T40_fuelCut             ; Re-init counter to 1 sec (Apply fuel cut only after threshold is exceeded for more than 1s)

            ;-----------------------------------------------------------------
            ; Section to update the state1 flags from various conditions 
            ;
            ; Bits in b are used to accumulate various loads and states
            ; In this section, b is only set in case we have 
            ; to bail to the state1 flag setting section
            ;-----------------------------------------------------------------
L1084       ldab    #$30                    ; Starting "state1" value, b=00110000 (not rotating)                          
            brclr   state1, #$20, L1085     ; Bail if this is the first time we compute state1??                               
            ldaa    T40_engRot              ;                                     
            beq     L1085                   ; Bail if engine not rotating                             
            ldaa    T40_noPower             ;                               
            bne     L1086                   ; Don't bail if timer not expired???                             
L1085       jmp     L1100                   ; bail
                                     
            ;----------------------------------------------------
            ; Engine rotating, check if key is in "start"
            ; In this section, b is only set in case we have 
            ; to bail to the state1 flag setting section
            ;----------------------------------------------------
L1086       ldab    #$21                     ; pre-load new state1 in case we have to bail, b=00100001 (startingToCrank)                           
            brset   port3Snap0, #$40, L1089  ; branch to next state if key not in start???

            ;----------------------------------------------------
            ; Key is in "start", check if rpm is higher than
            ; threshold (engine running?)
            ;----------------------------------------------------
            ldaa    #$0e                    ; starting rpm value (RPM/31.25) $0e = 437.25
            brset   state1, #$01, L1087     ; Branch if engine rotating bit was previously set
            ldaa    #$0b                    ; $0b = 343.75RPM                             
L1087       brclr   injFlags0, #$20, L1088  ; Branch if temperature(ectFiltered) >= -8degC
            adda    #$02                    ; temperature(ectFiltered) < -8degC, add 62.5 RPM                             
L1088       cmpa    rpm31                   ; compare threshold to current engine speed                              
            bhi     L1085                   ; Bail if engine rpm lower than calculated value                             

            ;---------------------------------------------------------------------
            ; At this point, 
            ; key is in "start" or engine rpm is higher than minimum threshold, 
            ; minimum conditions are therefore met for the engine to start or be started?
            ; 
            ; Use this state to check if we should get fuel injection. If we get stuck in
            ; this state it means engine is rotating but something is wrong...
            ;---------------------------------------------------------------------
            ;---------------------------------------------------------------------
            ; If enough time has elapsed, check if CAS is working normally
            ;---------------------------------------------------------------------
L1089       ldab    #$28                    ; pre-load new state1 in case we have to bail, b=00101000  (trying to start but something is wrong...)                          
            ldaa    T40_start               ;                              
            adda    #$50                    ; add 2s                            
            bcs     L1090                   ; Branch if key was out of start for less than 2s (when engine was upgraded from startingToCrank),                             
            brclr   faultHi, #$80, L1090    ; Its been more than ~2s since key was out of start, ECU has had enough time to check if CAS was working, check it, branch if no fault on CAS
            ldaa    tdcCasCount             ; Fault code set...                             
            cmpa    #$04                    ;                             
            bcs     L1085                   ; Bail if tdcCasCount<4, this should not have happened at this time since engine has been rotating for a while                           

            ;----------------------------------------------------------------------
            ; Bail if fuel cut is active (T40_fuelCut=0)
            ;----------------------------------------------------------------------
L1090       ldaa    T40_fuelCut             ; Fuel cut timer                              
            beq     L1085                   ; Bail if timer 0 (fuel cut is active)                             

            ;-----------------------------------------------
            ; Bail if ECU is about to be shutoff
            ;-----------------------------------------------
            brset   port3, #$02, L1085      ; Bail if IG1 at 0V, ECU is about to turn off after delay...?

            ;-------------------------------------------------------------------------
            ; At this point, minimum conditions are met for the engine 
            ; to start or run (rpm>thresh or start switch on), CAS is working,
            ; there is no fuel cut and the ECU is not being turned off
            ;
            ; Basically we know that we should be injecting fuel, do a little more check below...
            ;
            ;
            ; Calculate a maximum rpm that we should have based on maxRpm = baseRpm + rpmOffset
            ; where rpmOffset is additional loads that we calculate below
            ;
            ; Below, a will contain baseRpm and b will be used to accumulate the additional loads as flags...
            ;-------------------------------------------------------------------------
            ;-----------------------------------------------
            ; Get Initial RPM from ECT interpolated table
            ;-----------------------------------------------
            ldx     #t_rpmEct               ;                                 
            jsr     interpEct               ;                                    
            tba                             ; a = initial rpm idle speed, will be changed below (L1095)                               
            clrb                            ; b = 00000000, no additionnal loads yet

            ;-----------------------------------------------------------------
            ; Check if T40s_Idle timer expired
            ; (when idle position switch has been on for more than 0.75s)
            ;-----------------------------------------------------------------
            tst     T40s_Idle               ;                                
            beq     L1091                   ; Branch if T40s_Idle already at zero (idle position switch on for more than 0.75s)                               

            ;----------------------------------------------------------------
            ; Timer not expired, decrement it at 40Hz
            ;----------------------------------------------------------------
            brclr   Tclocks, #$01, L1091    ; Branch if basic 40Hz signal not set
            dec     T40s_Idle               ; Decrement timer       
            brset   port3Snap0, #$20, L1091  ; Ignore timer if in Park or Neutral (no transmission load)                                
            beq     L1092                   ; Branch if T40s_Idle reached 0 this time 

            ;-------------------------
            ; Add a load when ???
            ;-------------------------
L1091       brclr   state1, #$04, L1093     ; Branch if state1.2 (idle too fast) was not previously set
L1092       incb                            ; Add load
L1093       .equ    $

            ;--------------------------
            ; Add "transmission" load
            ;--------------------------
#ifdef E932
            brset   port3Snap0, #$20, L1094  ; Branch if in Park or Neutral                              
            addb    #$02                    ; Set flag indicating "transmission load"
#endif
            ;--------------------------
            ; Add "A/C" load
            ;--------------------------
L1094       brset   port3Snap0, #$10, L1095  ; Branch if air conditioning switch is off (reverse logic)                            
            addb    #$04                    ; A/C on, set flag b += 00000100                                

            ;---------------------------------------------------------
            ; Compute total rpm threshold from  baseRpm+rpmOffset
            ;---------------------------------------------------------
L1095       ldx     #t_rpmEctOff            ; x points to table of offsets                              
            abx                             ; c points to desired offset
            adda    $00,x                   ; a = baseRpm+rpmOffset

            ;---------------------------------------------------------------------
            ; Based on that threshold, compute which state we will end-up with
            ;---------------------------------------------------------------------
            ;--------------------------------------------------------
            ; If current rpm<threshold, use state1=00100000 (normal)
            ;--------------------------------------------------------
            cmpa    rpm31                   ; compare to current rpm
            bhi     L1099                   ; Branch if current rpm lower than calculated value (engine is running normally?)
#ifdef E931
            brset   ftrimFlags, #$08, L1099 ; RPM is higher than threshold, branch anyway if speed>24km/h and IG2 related signal is set on E931??????
#endif

            ;-----------------------------------------------------
            ; rpm > threshold 
            ; if air volume low, use state1=00101100 
            ; i.e. runningFast and rotatingStopInj
            ;-----------------------------------------------------
            brset   state2, #$08, L1096     ; Skip airVolT check / branch if no pulse accumulator interrupts received (mas broken, skip airFlow check?)
            ldaa    T2_airVolT              ;                             
            beq     L1098                   ; Branch if airVolT below threshold for more than 5s 

            ;-----------------------------------------------------
            ; rpm > threshold and air volume high
            ; If engine was started less than 5s ago, use state1=00100000 (normal)
            ; i.e. high rev upon startup is normal
            ;-----------------------------------------------------
L1096       ldaa    T2_crank                 ;                             
            adda    #$0a                     ;                              
            bcs     L1099                    ; branch if engine stopped "startingToCrank" less than 5s ago...
            brset   iscLrnFlags, #$20, L1099 ; branch if iscStStall has been updated

            ;------------------------------------------------------------------------------
            ; rpm > threshold and air volume high and engine started more than 10s ago
            ; If idle switch is off, use state1=00100000 (normal)
            ; i.e. we are stepping on the gas...
            ;------------------------------------------------------------------------------
            ldaa    T40s_Idle               ;                              
            bne     L1099                   ; Branch if timer not yet 0, idle switch not on for more than 0.75s

            ;---------------------------------------------------------------------------------
            ; rpm > threshold and air volume high and engine started more than 10s ago 
            ; and idle switch has been on for more than 0.75s
            ; use state1 = 00101100
            ; i.e. runningFast and rotatingStopInj
            ;---------------------------------------------------------------------------------
L1098       ldab    #$2c                    ; b=00101100, this means the engine is running too fast                              
            bra     L1100                   ;                              
L1099       ldab    #$20                    ; use b=00100000 (normal)

            ;-------------------------------------------------------------
            ; Set state1 flag if we are not receiving mas interrupts
            ;-------------------------------------------------------------
L1100       brclr   state2, #$08, L1101     ; Branch if pulse accumulator interrupts received
            orab    #$02                    ; Set flag indicating we are not receiving pulse accumulator interrupts received

            ;------------------------------------------------
            ; At this point b has been set in preceeding 
            ; code to indicate current state, update state1
            ;------------------------------------------------
L1101       ldaa    state1                  ;                               
            anda    #$80                    ; Reset all except closed loop mode flag
            aba                             ; Tranfser other flags set in code above                            
            staa    state1                  ; Store new state                               

            ;------------------------------------------------------
            ; Compute index into maf compensation table t_masComp
            ; since the values it contains are not equally spaced.
            ; Basically remaps mafRaw16...
            ;
            ; Note that this mapping is the same for 1G and 2G
            ; maf such that it doesn't need to be changed in case
            ; 2G maf is used in 1G...
            ;------------------------------------------------------
            ldd     mafRaw16                ; d = 16 bit mafRaw (a=mafRaw16/256)                                
            ldy     #L2054                  ;                               
            jsr     pwiseLin                ; d = T(L2054, mafRaw16) (a=T(L2054, mafRaw16/256))                                  
            std     temp2                   ; temp2:temp3 = T(L2054, mafRaw16)                              
            jsr     scale16m                ; d = T(L2054, mafRaw16)/16 (b=16*T(L2054, mafRaw16/256))                               
            cmpb    #$80                    ; Check for max of $80. Since max(T(L2054, mafRaw16/256))=20=1600Hz, we trim at $80/16=8=200Hz! 
            bcs     L1103                   ;                              
            ldab    #$80                    ; Use max of $80       
            
            ;------------------------------------------------------------
            ; Compute total maf compensation = masComp + t_masComp(Hz)
            ;------------------------------------------------------------
L1103       stab    temp5                   ; temp5 = T(L2054, mafRaw16)/16 with max of $80                              
            ldx     #t_masComp              ; x point to masCompensation table                                   
            ldd     temp2                   ; d = T(L2054, mafRaw16)                              
            jsr     interp1                 ;                                
            clra                            ; d = t_masComp(T(L2054, mafRaw16))
            addb    #masComp                ; b = masComp + t_masComp(T(L2054, mafRaw16))                                 
            rola                            ; propagate carry bit in a,
            std     temp6                   ; temp6:temp7 = d = t_masComp(T(L2054, mafRaw16)) = total MAS compensation                              

            ;-------------------------------------------------------------------------
            ; Compute conditioned L1992(iat) and compensate for barometric pressure
            ;-------------------------------------------------------------------------
            ldx     #L1992                  ;                               
            jsr     iatCInterp              ; b = L1992(iat)                                  
            ldaa    #$cd                    ; $cd is 1 bar for baroChecked                            
            mul                             ; d = $cd*L1992(iat)                           
            asld                            ; d = 2*$cd*L1992(iat)                            
            div     baroChecked             ; d = 2*$cd*L1992(iat)/baroChecked                                   
            lsrb                            ; b = $cd*L1992(iat)/baroChecked = L1992(iat) * $cd/baroChecked = L1992(iat)*baroFactor where baroFactor=$cd/baroChecked equals 1.0 if baroChecked=1bar                              
            adcb    #$00                    ; Round up result
            ldx     #$5222                  ;                               
            jsr     clipOffset              ; b = max(min(L1992(iat)*baroFactor,$52)-$22,0)                                   

            ;-----------------------------------------------------------------------
            ; Compute airflow sensor linearity compensation factor from 2D table t_masLin 
            ; using max(min(L1992(iat)*baroFactor,$52)-$22,0)/16 for rows 
            ; and T(L2054, mafRaw16)/16 for columns, see t_masLin description
            ;-----------------------------------------------------------------------
            ldx     #t_masLin               ;                                     
            ldy     #$0900                  ;                               
            ldaa    temp5                   ;                              
            jsr     lookup2D2               ; a = b = 2D interpolated t_masLin                                  
            stab    masLinComp              ; 
            jsr     mul816_128              ; d = masLinComp * (masComp+t_masComp(xx))/128
            std     totMasComp              ; totMasComp =(masComp+t_masComp(xx)) *  t_masLin(xx)/128

            ;-------------------------------------------------------------
            ; Section to check if the o2 sensor is operating normally
            ;-------------------------------------------------------------
            ;-------------------------------------------------------------
            ; If engine is notRotating, init rich/lean flag 
            ; and o2 sensor bad flag to default values 
            ;-------------------------------------------------------------
            brclr   state1, #$10, L1106     ; Branch if notRotating clear 
            orm     closedLpFlags, #$c0     ; Assume o2Raw is rich and o2 sensor bad
            ldaa    o2Raw                   ; a = o2Raw                              
            cmpa    #$1f                    ;                             
            bcc     L1105                   ; Branch if o2Raw >= 0.6v (rich)                            
            andm    closedLpFlags, #$7f     ; o2Raw is lean, reset bit                                
L1105       bra     L1114                   ; Bail                              

            ;-------------------------------------------------------
            ; Choose how long to wait to check o2 sensor voltage 
            ; depending on ect (o2 sensor warm-up time...)
            ;-------------------------------------------------------
L1106       ldaa    T2_crank                ; a = T2_crank                                 
            ldab    ectFiltered             ;                                    
            cmpb    #$54                    ; 41degC                             
            bcs     L1108                   ; Branch if temperature(ectFiltered) > 41degC                              
            adda    #$58                    ; a = T2_crank + $58  (44sec)                           
            bra     L1109                   ;                              
L1108       adda    #$1e                    ; a = T2_crank + $1e  (15sec)                          

            ;---------------------------------------------------------------------------------------
            ; Update the rich/lean flag if sufficient time has elapsed since car was started 
            ;---------------------------------------------------------------------------------------
L1109       bcs     L1114                   ; bail if engine stopped "startingToCrank" less than 44 or 15 sec ago (depending en ect).                               
            ldaa    closedLpFlags           ; a = old closedLpFlags                               
            orm     closedLpFlags, #$80     ; Assume result will be rich
            ldab    o2Raw                   ; b = o2Raw                              
            cmpb    #$1f                    ;                              
            bcc     L1111                   ; Branch if o2Raw >= 0.6v (rich)                              
            andm    closedLpFlags, #$7f     ; o2Raw is lean, Reset flag                                 

            ;--------------------------------------------------------
            ; Check if flag value changed compared to the last time
            ;--------------------------------------------------------
L1111       eora    closedLpFlags           ; Compare old closedLpFlags t new one                              
            bmi     L1112                   ; Branch if rich/lean flag changed (reset o2 bad flag)                             

            ;-----------------------------------
            ; Rich/lean flag did not change
            ;-----------------------------------
            brclr   state1, #$80, L1113     ; Reset timer and bail if open loop mode

            ;----------------------------------------------
            ; Closed loop mode and flag did not change yet
            ; Check if timer is expired which would mean that
            ; something is wrong (in closed loop mode, o2 sensor
            ; voltage should have changed by now...)
            ;----------------------------------------------
            ldaa    T2_o2Sensor             ;                             
            bne     L1114                   ; Bail if timer not yet expired                             
            orm     closedLpFlags, #$40     ; Timer expired, set o2 bad flag                               
            bra     L1114                   ; Bail
                                         
            ;------------------------------
            ; Reset flag and restart timer
            ;------------------------------
L1112       andm    closedLpFlags, #$bf     ; reset o2 bad flag                               
L1113       ldaa    #$28                    ; 20sec                            
            staa    T2_o2Sensor             ; re-init timer to 20sec                             

            ;--------------------------------------------------------------
            ; Re-init T40_stInj0 to 1 sec if engine is not rotatingStopInj
            ; This means that T40_stInj0 starts counting when state 
            ; changes to rotatingStopInj
            ;--------------------------------------------------------------
L1114       brset   state1, #$08, L1115     ; Branch if engine rotatingStopInj?                                
            ldaa    #$28                    ; 1 sec                            
            staa    T40_stInj0              ;                              
            bra     L1116                   ;                              

            ;----------------------------------------------------------------
            ; Re-init timer T40_stInj1 to 2 sec if engine 
            ; is rotatingStopInj and T40_stInj0 expired
            ; This means that T40_stInj1 is only init when rotatingStopInj
            ; has been active for more than 1 sec and will start counting
            ; when rotatingStopInj is no more active. Will expire 2sec later.
            ;----------------------------------------------------------------
L1115       ldaa    T40_stInj0                ;                              
            bne     L1116                     ; Branch if timer not expired                             
            ldaa    #$50                      ;                             
            staa    T40_stInj1                ;
                                          
            ;-------------------------------------------------------------
            ; Section to decide between closed loop and open loop mode
            ; (set/reset state1.7)
            ;-------------------------------------------------------------
            ;-------------------------------------------------------------
            ; Have y point to airVol or airVolTB depending on baroChecked 
            ;-------------------------------------------------------------
L1116       ldy     #airVol                   ;                               
            ldaa    baroChecked               ;                                    
            cmpa    #$9c                      ;                             
            bcs     L1117                     ; Branch if baroChecked<0.76bar (I think??)                               
            ldy     #airVolTB                 ;                               

            ;--------------------------------------------------------
            ; Check airVolTB for first threshold (with hysteresis)
            ;--------------------------------------------------------
L1117       ldx     #t_closedLp1               ;
            jsr     interp16rpm                ; b = t_closedLp1(rpm)                                    
            brclr   closedLpFlags, #$01, L1118 ; Branch if we were not above the threshold the last time we checked                              
            subb    #$06                       ; b =  t_closedLp1(rpm)-6 (hysteresis)                              
            bcc     L1118                      ; Branch if no underflow                             
            clrb                               ; Use min of 0                            
L1118       andm    closedLpFlags, #$fc        ; Reset 000000011                               
            cmpb    $00,y                      ; Notice implicit y = y + 1 here!!!!!!!!!!!
            bls     L1119                      ; Branch if t_closedLp1(rpm) <= airVol or airVolTB                              
                                              
            ;---------------------------------------------------------
            ; airVolTB smaller than threshold, closed loop is 
            ; therefore an option. Re-init timer T2_closedLp to 20sec 
            ; or 12sec and then continue trying to go to closed loop
            ;---------------------------------------------------------
#ifdef E931
            ldaa    #$28                      ; 20 sec                            
#else                                        
            ldaa    #$18                      ; 12 sec                           
#endif                                       
            staa    T2_closedLp                                                   
            bra     L1122                     ; Branch to continue closed loop checking                              

            ;--------------------------------------------------------------------------------
            ; At this point airVolTB is higher than first threshold. Normally, 
            ; the airflow is too high to be in closed loop mode but in order to account
            ; for variations, we will remain in closed loop for a certain time
            ; (T2_closedLp) as long as we are below a second threshold t_closedLp2(rpm). If 
            ; we go over that second threshold, we go to open loop immediatly. This is 
            ; implementing aiflow hysteresis under specific rpm conditions
            ;
            ; Check if airVolTB higher than second threshold (with an hysteresis of 6)
            ;--------------------------------------------------------------------------------
L1119       orm     closedLpFlags, #$01       ; Set flag indicating we are above the first threshold                               
#ifdef E931                                   
            ldx     #t_closedLp2              ;                                     
            jsr     interp16rpm               ; b = t_closedLp2(rpm)
#else                                         
            jmp     L1978                     ; Jump to code patch for E932 rpm calculation..., jumps back here afterwards...                             
L1120       jsr     interp16b                 ;                                  
#endif                                        
            brset   state1, #$80, L1121       ; Branch if closed loop mode
            subb    #$06                      ; b = t_closedLp2(rpm)-6 (threshold hysteresis)
            bcc     L1121                     ; Branch if underflow                             
            clrb                              ; Use min of 0                            
L1121       decy                              ; y points back to airVol or airVolTB (implicit y=y+1 above...)                             
            cmpb    $00,y                     ; Notice implicit y = y+1 here!!!!!!!!!!!
            bls     L1126                     ; Use open loop if airVolTB higher than second threshold

            ;---------------------------------------------------------
            ; airVolTB smaller than second threshold, we could 
            ; therefore remain in closed loop if timer not expired
            ;
            ; Check if T2_closedLp timer is expired
            ;---------------------------------------------------------
            ldaa    T2_closedLp               ;                             
            beq     L1126                     ; Use open loop mode if T2_closedLp expired                             

            ;----------------------------------------------------
            ; Check tspRaw threshold with hysteresis to know 
            ; if closed loop is an option
            ;
            ; Go to open loop if 
            ;       tpsRaw >= t_closedLp3(rpm)
            ; Closed loop is possible if 
            ;       tpsRaw < t_closedLp3(rpm)-$0d (hysteresis)
            ;
            ;----------------------------------------------------
L1122       ldx     #t_closedLp3              ; x = t_closedLp3                                    
            jsr     interp16rpm               ; b = t_closedLp3(rpm)                                   
            brset   state1, #$80, L1124       ; Branch if closed loop mode
            subb    #$0d                      ; b = t_closedLp3(rpm) - $0d                            
            bcc     L1124                     ; Branch if no underflow                             
            clrb                              ; Use min of 0
L1124       cmpb    tpsRaw                    ;                               
            bls     L1126                     ; Branch to use open loop if  t_closedLp3(rpm)<= tpsRaw                             

            ;-----------------------------------------------------
            ; We could use closed loop, check a few more things
            ;-----------------------------------------------------
            brset   state1, #$1b, L1126        ; Use open loop if engine is either notRotating or rotatingStopInj or runningFast
            brset   coilChkFlags, #$80, L1126  ; Use open loop if ignition problem is detected                               
            brclr   ftrimFlags, #$80, L1126    ; Use open loop if airVolT < threshold (15 or 24, used for fTrim...). Means airflow is too low???                               
            orm     closedLpFlags, #$02        ; Set flag indicating we should be using closed loop mode????                                
            ldaa    T40_stInj1                 ;                                     
            bne     L1126                      ; Use open loop if rotatingStopInj has been active for more than 1 sec (and 2 sec after)                             
            brset   closedLpFlags, #$40, L1126 ; Use open loop if o2 sensor is bad                                
            ldaa    ectFiltered                ;                                  
#ifdef E931
            cmpa    #$6a                       ; 31degC                             
#else
            cmpa    #$70                       ; 28degC                             
#endif

#ifdef noClosedLoop
            bra     L1126                      ; 
#else
            bhi     L1126                      ; Use open loop if temperature(ectFiltered) < 31degC                              
#endif

            ;-----------------------------------------------------
            ; Use closed loop mode, set flag
            ;-----------------------------------------------------
            orm     state1, #$80              ; Go into closed loop mode
            bra     L1127                     ; Bail                             

            ;---------------------------------
            ; Use open loop mode, reset flag
            ;---------------------------------
L1126       andm    state1, #$7f              ; Go into open loop mode

            ;-----------------------------------
            ; Reset o2Fbk in some cases
            ; open loop for instance...
            ;-----------------------------------
L1127       brset   fpsBcsFlags, #$04, L1129  ; Branch to reset if the fuel pressure solenoid was just deactivated                               
            brset   varFlags0, #$02, L1130    ; Bail if hot start flag is set                              
            brset   state1, #$80, L1130       ; Bail if closed loop mode
L1129       ldd     #$8080                    ;                               
            std     o2Fbk                     ;                              

            ;--------------------------------------------------
            ; Re-init timer T40_o2Fbk to 4 sec if 
            ; currentTrimRange!=low (or high speed, E931 only)
            ;
            ; T40_o2Fbk will be 0 when the low trim range will 
            ; will have been used for more than 4 sec
            ;--------------------------------------------------
L1130       brclr   ftrimFlags, #$13, L1131   ; Branch if currentTrimRange=low and rpm<threshold
            ldaa    #$a0                      ; 4sec                            
            staa    T40_o2Fbk                 ; T40_o2Fbk = 4sec                             

            ;--------------------------------------------------------------------
            ; Find which table we should be using depending on config resistors
            ; (one of L1999, L2000, L2001, L2002)
            ;--------------------------------------------------------------------
L1131       ldx     #t_strap2                 ;                                  
            jsr     cfgLookup16               ; x =  t_strap2(2*(config2 & $03)) = tableAddress

            ;----------------------------------------------------------
            ; Use o2Fbk_dec:o2Fbk_inc = t_o2Fbk1 if timer expired 
            ; i.e. we have been in low trim range for more than 4sec
            ;----------------------------------------------------------
            ldaa    T40_o2Fbk                 ;                                
            bne     L1132                     ; Branch if timer not expired                             
            ldd     t_o2Fbk1                  ; Timer expired, use t_o2Fbk1                              
            bra     L1138                     ; Bail to store                             

            ;--------------------------------------------------------------------------
            ; Timer not expired, compute values for o2Fbk_dec:o2Fbk_inc
            ; from table pointed by x (see above, one of L1999, L2000, L2001, L2002)
            ; Use b as index into table. Start with b = 0
            ;--------------------------------------------------------------------------
L1132       clrb                              ; b = 0                            

            ;-------------------------------------------------------------
            ; b = b+1 if airVolTB >= threshold
            ; Threshold based on config resistors (AWD vs FWD???)
            ;-------------------------------------------------------------
            ldaa    airVolTB                  ; a = airVolTB                                
#ifdef E931                                   
            cmpa    #$40                      ;                             
            brclr   config2, #$80, L1133      ; Branch if ??? (same as branching if FWD)                                
            cmpa    #$40                      ;                             
#else                                         
            cmpa    #$48                      ;                             
            brclr   config2, #$80, L1133      ;                                 
            cmpa    #$50                      ;                             
#endif                                        
L1133       bcs     L1134                     ; Branch if airVolTB < threshold                             
            incb                              ; airVolTB > threshold, b +=1 (go to next value)                            

            ;-------------------------------------------------------------
            ; b = b+2 if rpm31 >= (1500rpm or 1406rpm)
            ;     b+4 if rpm31 >= (2094rpm or 2313rpm)
            ;-------------------------------------------------------------
L1134       ldaa    rpm31                     ;                              
            cmpa    #$2d                      ;                             
            brclr   config2, #$80, L1135      ;  Branch if ??? (same as branching if FWD)
#ifdef E931                                   
            cmpa    #$30                      ;                             
#else                                         
            cmpa    #$2d                      ;                             
#endif                                        
L1135       bcs     L1137                     ; Branch if rpm31 < threshold (1500rpm or 1406rpm)                              
            addb    #$02                      ; rpm31 > (1500rpm or 1406rpm, b += 2
            cmpa    #$43                      ; 2094rpm                            
            brclr   config2, #$80, L1136      ; Branch if ??? (same as branching if FWD)
#ifdef E931                                   
            cmpa    #$4a                      ; 2313rpm                             
#else                                         
            cmpa    #$43                      ; 2094rpm                            
#endif                                        
L1136       bcs     L1137                     ;                              
            addb    #$02                      ; rpm31 > (2313rpm or 2094rpm, b += 2

            ;---------------------------------------------
            ; interpolate table from x+b
            ; (x is one of L1999, L2000, L2001, L2002)
            ;---------------------------------------------
L1137       abx                               ;                             
            ldaa    $00,x                     ;                              
            ldab    $06,x                     ; ???????????                             
                                              
            ;------------------------------------------------
            ; Update o2Fbk_dec and o2Fbk_inc with new values
            ;------------------------------------------------
L1138       std     o2Fbk_dec                                                 

            ;-------------------------------------------------------------
            ; If we are in closed loop mode, limit the range of o2Fbk
            ; depending on ect and then compute o2FuelAdj (how much 
            ; fuel to add/remove based on o2 sensor in closed loop....)
            ;
            ; Notice that part of the code has been located somewhere 
            ; else... (L1973)
            ;-------------------------------------------------------------
            ldaa    #$80                    ; pre-load default value of $80 (no fuel adjustment)                            
            brclr   state1, #$80, L1148     ; Branch if open loop mode

            ;----------------------------------------------------
            ; We are in closed loop mode, limit the range
            ; of o2Fbk to $4d-$d6 or $2a-$d6 depending on ect 
            ;----------------------------------------------------
            jmp     L1973                   ; Jump to code snipet for closed loop mode, will jump back to main code as appropriate                             
            nop                                                          

            ;------------------------------------------------
            ; Continuation of code...
            ;------------------------------------------------
            ;---------------------------------------
            ; temperature(ectFiltered) > 86degC
            ; Check for min and max of $2a and $d6
            ;---------------------------------------
L1140       bcc     L1141                   ; Branch if o2Fbk >= $2a
            ldaa    #$2a                    ; Use min of $2a                            
            bra     L1142                   ;                              
L1141       cmpa    #$d6                    ;                             
            bcs     L1143                   ; Branch if o2Fbk < $d6
            ldaa    #$d6                    ; Use max of $d6                            

            ;--------------------------
            ; Store new value of o2Fbk  
            ;--------------------------
L1142       clrb                            ; Set lower 8 bit of o2Fbk                             
            std     o2Fbk                   ;                              

            ;-----------------------------------------------------------------------------
            ; Compute o2FuelAdj = o2Fbk +/-  t_closedLpV1(xx) or t_closedLpV2(xx) or $02
            ; where +/- depends on o2Raw (lean or rich). 
            ;-----------------------------------------------------------------------------
L1143       psha                            ; st0 = o2Fbk high byte
#ifdef E931                                 ;
            ldab    #$02                    ; b = $02                              
            ldaa    T40_ftrim2              ; a = T40_ftrim2                                   
            beq     L1146                   ; Branch if timer expired, use $02 instead of table values if conditions are stable on E931                             
#else                                       ;
            ldx     #t_closedLpV2           ; x = t_closedLpV2                              
            brset   port3Snap0, #$20, L1144 ; branch if Park/neutral                               
#endif
            ldx     #t_closedLpV1           ; x = t_closedLpV1                                
L1144       brclr   ftrimFlags, #$13, L1145 ; branch if trim range is low and rpm<threshold???
            inx                             ; go to next value in table                             
L1145       ldab    $00,x                   ; b = = t_closedLpV1(xx) or t_closedLpV2(xx)                               
L1146       ldaa    o2Raw                   ; a = o2Raw
            cmpa    #$1a                    ; 0.5V
            pula                            ; a = o2Fbk                             
            bcc     L1147                   ; Branch if o2Raw > 0.5V
            aba                             ; o2 lean, a = o2Fbk + t_closedLpV1(xx) or t_closedLpV2(xx)
            bcc     L1148                   ; branch if no overflow                              
            ldaa    #$ff                    ; Use max in case of overflow                            
            bra     L1148                   ; Branch to store o2FuelAdj
                                         
L1147       sba                             ; o2 rich, a = o2Fbk -  t_closedLpV1(xx) or t_closedLpV2(xx)
            bcc     L1148                   ; branch if no underflow
            clra                            ; Use min value of 0

            ;---------------------
            ; Store new o2FuelAdj
            ;---------------------
L1148       staa    o2FuelAdj               ; o2Fbk +/- table value for fuel compensation in closed loop                              

            ;-------------------------------------------------------------
            ; Transfer ftrimFlags to oldFtrimFlg, a = old oldFtrimFlg
            ;-------------------------------------------------------------
            ldaa    oldFtrimFlg             ;                                    
            ldab    ftrimFlags              ;                                   
            stab    oldFtrimFlg             ;                                    

            ;--------------------------------------------------------------
            ; Section to check whether conditions are sufficiently 
            ; stable to update fuel trims. Fuel trims are updated 
            ; only if T40_ftrim = 0
            ;
            ; Restart timer T40_ftrim at 5s under all the following conditions
            ;
            ;       if  fuel trim range changed
            ;       or  open loop mode
            ;       or  airVolTB too high
            ;       or  ectRaw malfunction
            ;       or  iatRaw malfunction
            ;       or  baroRaw malfunction
            ;       or  temperature(ectFiltered) < 86degC
            ;       or  temperature(iatChecked) >= 50degC
            ;       or  baroChecked < 0.76bar
            ;       or  baroChecked >= 1.05bar
            ;       or  accEnr not 0
            ;       or  airDiffNeg1 >= accEnrDiffT 
            ;       or  airVolT too small
            ;       or  purge solenoid activated
            ;       or  fuel pressure solenoid activated
            ;       or  T40_ftrim2 expired (E931)
            ;       or  T0p5_crCold not expired
            ;
            ;--------------------------------------------------------------
            eora    ftrimFlags              ;                               
            anda    #$03                    ; a = (oldFtrimFlg eor ftrimFlags) & $03
            bne     L1150                   ; Branch if trim rancge changed                             
            brclr   state1, #$80, L1150     ; Branch if open loop mode                                
            brset   closedLpFlags, #$01, L1150      ; Branch if airVolTB too high                              
            brset   state2, #$07, L1150     ; Branch if ectRaw, iatRaw or baroRaw in error                               
            ldaa    ectFiltered             ;                                    
#ifdef E931
            cmpa    #$1c                    ; 86degC                             
#else
            cmpa    #$1b                    ; 88degC                            
#endif
            bhi     L1150                   ; Branch if temperature(ectFiltered) < 86degC                             
            ldaa    iatChecked              ;                                   
            cmpa    #$49                    ;                             
            bls     L1150                   ; Branch if temperature(iatChecked) >= 50degC                              
            ldaa    baroChecked             ;                                    
            cmpa    #$9c                    ;                             
            bcs     L1150                   ; Branch if baroChecked < 0.76bar?                              
            cmpa    #$d8                    ;                             
            bcc     L1150                   ; Branch if baroChecked >= 1.05bar?                             
            ldaa    accEnr                  ;                               
            bne     L1150                   ; Branch if accEnr not 0 (we are applying enrichment during acceleration)                              
            ldaa    airDiffNeg1             ;                                    
            cmpa    accEnrDiffT             ;                                    
            bcc     L1150                   ; Branch if airDiffNeg1 >= accEnrDiffT (we will apply decceleration enrichment????)                             
            ldaa    airVolT                 ;                                
            cmpa    #$18                    ;                             
            bcs     L1150                   ; Branch if airVolT < $18 (air volume too low)                             
            brclr   port6, #$10, L1150      ; Branch if purge solenoid activated
            brclr   port5, #$10, L1150      ; Branch if fuel pressure solenoid activated                              
#ifdef E931
            ldaa    T40_ftrim2              ;                                    
            beq     L1150                   ; Branch if timer T40_ftrim2 expired on E931???                               
#endif
            ldaa    T0p5_crCold             ;                               
            beq     L1151                   ; Branch if T0p5_crCold expired, meaning its been more than 120sec since we started a cold engine (we can update trims...)
                                          
            ;-----------------------------------------------------
            ; Conditions not stable, Re-init T40_ftrim at 5 sec
            ;-----------------------------------------------------
L1150       ldaa    #$c8                    ; 5 sec                             
            staa    T40_ftrim               ;                               

            ;------------------------------------------------------------------
            ; Get current fuel trim value according to current fuel trim range 
            ;------------------------------------------------------------------
L1151       ldx     #ftrim_low              ;                               
            ldab    ftrimFlags              ;                              
            andb    #$03                    ; Get current fuel trim range to update                            
            abx                             ; X point to fuel trim                             
            ldaa    $00,x                   ; a = fuelTrim                             
            ldab    #$80                    ; pre-load $80 in case we bail                     
                  
            ;----------------------------------------------
            ; Don't update trim if T40_ftrim not yet expired
            ;----------------------------------------------
            tst     T40_ftrim               ;                               
            bne     L1153                   ;                              

            ;-------------------------------------------------------------------------------
            ; Update fuel trim at 40Hz
            ; fuel trim is actually increased/decreased by 1 at 40Hz/(256/5) = 0.78125Hz
            ;-------------------------------------------------------------------------------
            brclr   Tclocks, #$01, L1154    ; Branch if 40Hz signal not set                                   
            ldab    o2Fbk                   ; b = o2Fbk
            cmpb    #$80                    ; 
            beq     L1154                   ; branch if o2Fbk = 100% (no update)
            ldab    ftrimCntr               ; b = ftrimCntr                             
            bcs     L1152                   ; branch if o2Fbk < 100%
            addb    #$05                    ; b = ftrimCntr + 5
            adca    #$00                    ; a = fuelTrim+1 if ftrimCntr rolled over (o2Fbk + 5)>255
            bra     L1153                   ;
L1152       subb    #$05                    ; b = ftrimCntr - 5
            sbca    #$00                    ; a = fuelTrim-1 if ftrimCntr rolled under (o2Fbk - 5)<0

            ;------------------------------
            ; Update ftrimCntr with new value
            ;------------------------------
L1153       stab    ftrimCntr               ;                              

            ;------------------------------------------------
            ; Check a = updated trim value for min/max values
            ;------------------------------------------------
L1154       cmpa    #$68                    ; 
            bcc     L1155                   ; Branch if new fuelTrim > $68 (81%)
            ldaa    #$68                    ; use min
L1155       cmpa    #ftrimMax               ;                                  
            bls     L1156                   ; Branch if new fuelTrim <= max (~140%)
            ldaa    #ftrimMax               ; use max

            ;---------------------------------------------------------------
            ; Update the stored fuel trim with updated value (in a) and decide
            ; whether we will apply the fuel trim to injector pulse width
            ;---------------------------------------------------------------
L1156       staa    $00,x                      ; Store new fuel trim value
            ldaa    #$80                       ; Assume we won't apply fuel trim, a = $80 (100% fuel trim) 
            brset   state2, #$08, L1157        ; Branch to use 100% if pulse accumulator interrupts are not being  received
            brset   closedLpFlags, #$01, L1157 ; Branch to use 100% if the "air volume (airVolTB) is too high to use closed loop mode (first threshold)"
            ldaa    $00,x                      ; Load fuel trim from the current range                                                
L1157       staa    workFtrim                  ; Store working fuel trim

            ;--------------------------------------------------------
            ; Compute coldTempEnr, fuel enrichment factor when engine
            ; is cold...Depends on ect and airflow 
            ;
            ; coldTempEnr/$80 = 1 + (f1-1)*f2 
            ;                   1 + ectNetEnrichment*f2 
            ;
            ;       where f1 is t_ectEnr(ectCond)/$80, f1>=1.0
            ;             f2 is t_airEnr(airVolCond)/$80, f2>=1.0
            ;
            ; Basically this factor adds fuel enrichment under 
            ; cold temperature which is reduced down to no enrichement
            ; (coldTempEnr/$80=1.0) as airVolCond increases, i.e. fuel
            ; enrichement is only required under low temperature and 
            ; low airflow
            ;--------------------------------------------------------
            ldx     #t_ectEnr               ;                               
            jsr     interpEct               ; b = t_ectEnr(ectCond)                                 
            clra                            ;                             
            subb    #$80                    ; d = t_ectEnr(ectCond)-$80                             
            bcc     L1158                   ; Branch if no overflow                             
            clrb                            ; Use min of 0                            
L1158       std     temp6                   ; temp6:temp7 = t_ectEnr(ectCond)-$80  
            ldx     #t_airEnr               ;                               
            ldaa    airVolCond              ;                                   
            jsr     interp16b               ; b = t_airEnr(airVolCond)                                  
            ldaa    rpm31                   ;                              
            cmpa    #$30                    ;                             
            bcc     L1159                   ;                              
            ldab    #$80                    ; Use b=$80 if rpm<1500 
L1159       jsr     mul816_128              ; d = t_airEnr(airVolCond) * (t_ectEnr(ectCond)-$80)/$80 
            addb    #$80                    ; b =  t_airEnr(airVolCond)*(t_ectEnr(ectCond)-$80)/$80 + $80                             
            stab    coldTempEnr             ; coldTempEnr = t_airEnr(airVolCond) * (t_ectEnr(ectCond)-$80)/$80 + $80
                                            
                                         
            ;----------------------------------------------------------------
            ; Section to update openLoopEnr enrichment factor if in open loop
            ;----------------------------------------------------------------
            ldab    #$80                    ; Assume an enrichement factor of 1.0                            
            brset   state1, #$80, L1167     ; Branch if closed loop mode     
            
            ;-------------------------------------------------------------
            ; Open loop
            ; Compute conditionned rpm and load for 2D map interpolation                           
            ;-------------------------------------------------------------
            ldab    rpm31                   ; b = rpm31
            ldaa    #$d0                    ; 6500 RPM                                                                
            jsr     rpmRange                ; get rpm for map interpolation, b = min(max(RPM31p25-#$10, 0), $d0) = min(max(RPM31p25-500rpm,0),6500rpm)  
            stab    temp6                   ; temp6 = conditionned rpm
            jsr     getLoadForMaps          ; get the load value for map interpolation                                                      
            stab    temp7                   ; temp7 = conditionned load                              

            ;----------------------------------------------
            ; Get basic fuel enrichement from 2D fuel map
            ;----------------------------------------------
            ldx     #t_fuelMap              ;                                   
            ldy     #$0e00                  ;                               
            jsr     lookup2D                ; a = b = 2D interpolated fuel map value from temp6 (rpm) and temp7 (load)                               

            ;----------------------------------------
            ; Check airVol vs. RPM (deceleration???)
            ;----------------------------------------
            ldaa    airVol                  ;                                
            cmpa    #$af                    ;                             
            bcs     L1162                   ; branch if airVol<$af                              
            ldaa    rpm31                   ;                              
#ifdef E931
            cmpa    #$46                    ; 2187rpm                            
#else
            cmpa    #$53                    ; 2594rpm                            
#endif
            bcs     L1162                   ; branch if current rpm smaller than threshold                              
            ldaa    timFuelEnr              ; a = timing/knock based fuel enrichement                              
            aba                             ; a = basicFuelEnrichement + timingKnockFuelEnrichment
            bcs     L1163                   ; branch if overflow                             
            tab                             ; b = basicFuelEnrichement + timingKnockFuelEnrichment

            ;-----------------------------------------------------------------------
            ; Check  fuel compensation + timing/knock based enrichment for max value
            ;-----------------------------------------------------------------------
L1162       cmpb    #fuelMapClip            ; 
            bls     L1164                   ; Branch if below max                              
L1163       ldab    #fuelMapClip            ; Use max                            
L1164       pshb                            ; Store  basicFuelEnrichement + timingKnockFuelEnrichment on stack
                            
            ;-----------------------------------
            ; Compute TPS based fuel enrichment
            ;-----------------------------------
            ldab    tpsRaw                  ;
            ldx     #$b080                  ;                                
            jsr     clipOffset              ; b = max(min(tpsRaw,$b0)-$80,0)-> returns b = $00 to $30  (50% to 69%)                                           
            tba                             ; a = conditionned TPS for table interpolation                            
            ldx     #t_tpsEnr               ;                                
            jsr     interp16b               ; a = t_tpsEnr(tpsRaw)                                 

            ;-----------------------------------------------------------------------------------------
            ; Keep the highest of t_tpsEnr(tpsRaw) and  "basicFuelEnrichement + timingKnockFuelEnrichment"
            ;-----------------------------------------------------------------------------------------
            pulb                            ; b = basicFuelEnrichement + timingKnockFuelEnrichment
            cba                             ;                              
            bcs     L1165                   ; branch if basicFuelEnrichement + timingKnockFuelEnrichment
            tab                             ; b = max(t_tpsEnr(tpsRaw), basicFuelEnrichement + timingKnockFuelEnrichment)

                                          
            ;-----------------------------------------------------------
            ; Compute timer T2_hotEnrich based fuel enrichement if required
            ;-----------------------------------------------------------
L1165       brclr   varFlags0, #$02, L1167  ; Bail if "hot start" flag was not set                              
            pshb                            ; save on stack                             
            ldab    #$30                    ; 
            ldaa    T2_hotEnrich            ;                             
            mul                             ;                             
            adda    #$80                    ; d = T2_hotEnrich*$30 + $80                            

            ;---------------------
            ; Keep the highest
            ;---------------------
            pulb                            ; b = max(t_tpsEnr(tpsRaw), basicFuelEnrichement + timingKnockFuelEnrichment)
            cba                             ;                             
            bls     L1167                   ;                              
            tab                             ; max(T2_hotEnrich*$30 + $80, t_tpsEnr(tpsRaw), basicFuelEnrichement + timingKnockFuelEnrichment)
            
            ;-------------------------------------------
            ; Update openLoopEnr with the above result
            ;-------------------------------------------
L1167       stab    openLoopEnr             ; Store final value                               

            ;------------------------------------------------------------------
            ; Update T2_hotEnrich and varFlags0.1 (hot start) used in timer based enrichement above
            ;------------------------------------------------------------------
            brclr   state1, #$90, L1168     ; Branch if notRotating and closed loop clear
            andm    varFlags0, #$fd         ; closedLoop or notRotating, reset flag and reset timer
            clra                            ; a = 0                             
            bra     L1169                   ; Update timer with 0

L1168       brclr   state1, #$01, L1171     ; open loop and at least rotating, Bail if startingToCrank clear
            ldaa    iatChecked              ; Engine startingToCrank, a = iatChecked
            cmpa    #$3a                    ;                             
            bhi     L1171                   ; Bail if temperature(iatChecked) < 60degC
            ldaa    ectFiltered             ;                                    
            cmpa    #$18                    ; 93degC                            
            bhi     L1171                   ; Bail if temperature(ectFiltered) < 93degC                             

            ;-----------------------------------------------------------------------------
            ; At this point, engine is startingToCrank and we are in open loop 
            ; and temperature(iatChecked) >= 60degC and  
            ; temperature(ectFiltered) >= 93degC (hot start)                              
            ;
            ; Set hot start flag, init o2Fbk to lean(??) and re-init T2_hotEnrich timer to 120sec  
            ;-----------------------------------------------------------------------------
            orm     varFlags0, #$02         ; Set varFlags0.1 flag (hot start)
            ldaa    #$d6                    ;                             
            ldab    #$80                    ;                             
            std     o2Fbk                   ; o2Fbk = $d680 (lean?)                             
            ldaa    #$f0                    ; Re-init timer with 120sec                            
L1169       staa    T2_hotEnrich            ;                             

            ;----------------------------------------------
            ; Update enrWarmup when engine startingToCrank
            ; get enrWarmup timer value from table
            ;----------------------------------------------
L1171       clrb                            ;                             
            brset   state1, #$10, L1172     ; Branch if notRotating
            brclr   state1, #$01, L1173     ; Branch if startingToCrank clear
            ldx     #t_enrWarmup            ;                               
            jsr     interpEct               ;                                  
L1172       stab    enrWarmup               ;                              
            bra     L1174                   ;
                                          
            ;-----------------------------------------------------------------------------------------
            ; Update enrWarmup at 40Hz
            ;
            ; T_enrWarm is decremented at 40Hz and loops at 2 if enrWarmup>$1a or loops 
            ; at $18 otherwise decrement enrWarmup each time T_enrWarm reaches 0
            ;
            ; This allows to have rapid lowering of enrWarmup at first and then slow one
            ; enrWarmup is decremented at 20Hz until it reached $1a (fuel enrichment factor of 141%) 
            ; and then at 1.67Hz 
            ;-----------------------------------------------------------------------------------------
L1173       brclr   Tclocks, #$01, L1176    ; Bail if 40Hz signal not set 
            ldaa    enrWarmup               ;                              
            beq     L1176                   ;                              
            dec     T_enrWarm               ;                              
            bne     L1176                   ;                              
            dec     enrWarmup               ;                              

L1174       ldaa    #$02                    ;                             
            ldab    enrWarmup               ;                              
            cmpb    #$1a                    ;                             
            bhi     L1175                   ; Branch if enrWarmup>$1a                             
            ldaa    #$18                    ; Reset T_enrWarm counter to $18                            
L1175       staa    T_enrWarm               ;                              


            ;------------------------------------------------
            ; Section to compute injFactor 
            ; start with basic value of totMasComp*16  
            ;------------------------------------------------
L1176       ldd     totMasComp              ; d = totMasComp                                   
            asld                            ;                             
            asld                            ;                             
            asld                            ;                             
            asld                            ;                             
            std     temp6                   ; temp6:temp7 = totMasComp*16

            ;---------------------------------------
            ; Factor in injector size compensation
            ;---------------------------------------
            ldab    #injComp                ; Injector size compensation factor ($80 = 100% = no compensation, referenced at 260cc, 36psi)                                
            jsr     mul816_128              ; d = [temp6:temp7] = totMasComp*16 * injComp /128                                   
            std     injMasComp              ; injMasComp = totMasComp*16 * injComp/128                              

            ;-------------------------------------------------------
            ; Factor in working fuel trim and 02 fuel adjustment
            ; Done this way, total range is limited to [50%,150%]
            ; when both workFtrim and o2FuelAdj are at $00 or $ff  
            ;-------------------------------------------------------
            clra                              ; a=0                            
            ldab    workFtrim                 ; d = working fuel trim ($80=100%)                             
            addd    #$0100                    ; d = workFtrim + 2*$80                               
            addb    o2FuelAdj                 ; Add o2 adjustment (Add/remove fuel based on o2 sensor voltage/feedback, $80=100%->no fuel adjustment)                              
            adca    #$00                      ; propagate carry, d = workFtrim + o2FuelAdj + 2*$80                            
            jsr     mul1616_512               ; D = [temp6:temp7] = [workFtrim + o2FuelAdj + 2*$80]/512 * [temp6:temp7]

            ;-----------------------------------
            ; Factor-in air temp, baro, etc...
            ;-----------------------------------
            ldab    iatCompFact               ; Correct for air temperature (air density)                                    
            jsr     mul816_128                ; D and [temp6:temp7] = b*[temp6:temp7]/128                                   
            ldab    baroFact                  ; Correct for barometric pressure (air density)                                 
            jsr     mul816_128                ; D and [temp6:temp7] = b*[temp6:temp7]/128                                   
            ldab    openLoopEnr               ; Apply the open loop enrichment factor, based on timing/knock, tps and timer
            jsr     mul816_128                ; D and [temp6:temp7] = b*[temp6:temp7]/128                                   
            ldab    coldTempEnr               ; Add fuel enrichement under cold engine temperature and low airflow
            jsr     mul816_128                ; D and [temp6:temp7] = b*[temp6:temp7]/128                                   
            ldab    enrWarmup                 ; b = enrichment during warmup/startup, from t_enrWarmup(ECT), can reach 300% in very cold temp but is decreased to 140% very rapidly
            clra                              ; a=0                            
            asld                              ; d = 2*enrWarmup                            
            addd    #$0080                    ; d = 2*enrWarmup + $80 
            jsr     mul1616_128               ; Apply (2*enrWarmup+$80) enrichment factor
            std     injFactor                 ; Store final result in injFactor (global injector factor)                            

            ;----------------------------
            ; Compute injector deadTime
            ;----------------------------
            ldx     #t_deadtime-2                                            
            ldaa    battRaw                                                 
            jsr     interp32                                                 
            stab    deadTime
            
            ;-----------------------------------------
            ; Update injFlags0.2 (set but not reset???) 
            ;-----------------------------------------
            ldaa    rpm31                                                 
            cmpa    #$0e                                                 
            bcs     L1178                     ; branch if rpm < 437.5                              
            orm     injFlags0, #$04           ; rpm >= 437.5, set bit                               

            ;-----------------------------------------------
            ; Update injFlags0.1.3.5 if engine notRotating
            ;-----------------------------------------------
L1178       brclr   state1, #$10, L1180       ; Branch if notRotating clear
            andm    injFlags0, #$df           ; assume we reset 00100000, updated below
            ldaa    ectFiltered               ;                                    
            cmpa    #$c2                      ; -8degC                            
            bcs     L1179                     ; Branch if temperature(ectFiltered) > -8degC                              
            orm     injFlags0, #$20           ; temperature(ectFiltered) <= -8degC, set bit                                 
L1179       brclr   injFlags0, #$04, L1180    ; Branch if rpm<437.5                                
            andm    injFlags0, #$fa           ; Reset 0000 0101                                

            ;------------------------------------------------------------------------------------
            ; Section to compute injPwStart, the injector pulsewidth when engine "startingToCrank" 
            ;
            ;  startingToCrank   "cold engine"   injPwStart       injFlags0.7 (startingToCrankColdEngine)
            ;          0             0               0                0
            ;          0             1               0                0
            ;          1             0            pulseWidth*4        0
            ;          1             1             pulseWidth         1
            ;------------------------------------------------------------------------------------
            ;--------------------------------
            ; Get starting value from L2008
            ;--------------------------------
L1180       clra                                                         
            brclr   state1, #$01, L1191     ; Bail to end of section if startingToCrank clear
            ldx     #L2008                  ; Engine is startingToCrank                               
            jsr     interpEct2              ; b = L2008(ectCond)                                   
            ldaa    #$80                    ; a = $80                            
            mul                             ;                             
            lsrd                            ; d = $80*L2008(ectCond)                           
            std     temp6                   ; [temp6:temp7] = $80*L2008(ectCond)                            

            ;--------------------------------------------
            ; Factor-in some enrichement if injCount<5 
            ; This only adds more fuel when starting to 
            ; crank for the first time under very cold 
            ; temperature (-16degC). Not sure as to 
            ; exactly why but at -16degC, I guess 
            ; it just might help???
            ;--------------------------------------------
            ldaa    injCount                  ;                              
            cmpa    #$05                      ;                              
            bcc     L1182                     ; Branch if injCount>=5                              
            ldx     #L2042                    ;                               
            jsr     interpEct2                ; b=L2042(ectCond)                                  
            clra                              ;                             
            addd    #$0080                    ; d = L2042(ectCond) + $80                               
            jsr     mul1616_128               ; [temp6:temp7] = [temp6:temp7] * (L2042(ectCond)+$80)/128

            ;------------------------------------------------------------
            ; Factor in an rpm dependent correction factor if rpm >125???
            ;------------------------------------------------------------
L1182       ldaa    rpm8                      ; a = rpm8                            
            cmpa    #$40                      ;                             
            bcs     L1183                     ; Branch if rpm < max of 500                              
            ldaa    #$40                      ; rpm>500, use max of 500rpm                            
                                              
L1183       suba    #$10                      ; a = rpm8-$10                             
            bcs     L1185                     ; Bail if rpm8<125rpm                             
            asla                              ; a = 2*(rpm8-$10)                             
#ifdef E931                                   
            ldab    #$56                      ;                             
#else                                         
            ldab    #$57                      ;                             
#endif                                        
            mul                               ; d = $56*2*(rpm8-$10)                             
            asld                              ;                             
            tab                               ; b = 2*$56*2*(rpm8-$10)/256                            
            ldaa    #$80                      ; a = $80                            
            sba                               ; a = $80 - $56*2*(rpm8-$10)/128                             
            bcc     L1184                     ; Branch if no underflow                             
            clra                              ; Use min of 0                            
L1184       tab                               ; b = $80 - $56*2*(rpm8-$10)/128                            
            jsr     mul816_128                ; [temp6:temp7] = [temp6:temp7] * ($80 - $56*2*(rpm8-$10)/128)/128
                                              

            ;------------------------------------------------------------------
            ; Check current value for minimum, keep min
            ; minimum is L2008(0) -> starting value at 86degC (hot engine)
            ;------------------------------------------------------------------
L1185       ldab    L2008                   ; b = L2008(0)                              
            ldaa    #$80                    ; a = $80                            
            mul                             ; d = $80*L2008(0)                            
            lsrd                            ; d = $80*L2008(0)/2                            
            cmpd1   temp6                   ;                              
            bcs     L1187                   ; branch if current value >                             
            std     temp6                   ;  
                                        
            ;--------------------------------
            ; Factor-in barometric pressure
            ;--------------------------------
L1187       ldab    baroFact                ;                                 
            jsr     mul816_128              ; d = pulseWidth = [temp6:temp7] = [temp6:temp7] * baroFact/128

            ;-----------------------------------------
            ; Multiply by 2 and check for overflow
            ;-----------------------------------------
            asld                            ; pulseWidth = d = 2*[temp6:temp7]                            
            bcc     L1188                   ; Branch if no overflow                              
            ldaa    #$ff                    ; Use max                             

            ;--------------------------------------------------------------
            ; At this point d = pulseWidth
            ;
            ; Set startingToCrankColdEngine flag if pulseWidth > threshold
            ; or reset it (with hysteresis) 
            ;
            ; Note that pulseWidth will be larger when the engine is cold, also rpm dependent...
            ;--------------------------------------------------------------
L1188       pshb                            ; Put b on stack for temp calculation
            ldab    #$35                    ; b = $35 = 13.6ms =threshold
            brclr   injFlags0, #$80, L1190  ; Branch if startingToCrankColdEngine was not previously set
            ldab    #$30                    ; Flag was set, use lower threshold (hysteresis) b=$30 = 12.3ms
L1190       orm     injFlags0, #$80         ; By default, assume startingToCrankColdEngine flag set
            cba                             ; 
            pulb                            ; restore b (lower part of pulseWidth)                             
            bcc     L1192                   ; Branch if pulseWidth/256 >= threshold (flag already set), we are startingToCrankColdEngine

            ;-------------------------------------------------------------------------
            ; pulseWidth < threshold, engine is therefore startingToCrank
            ; but the engine is not cold 
            ; Multiply pulseWidth by 4?????? and reset the flag
            ;-------------------------------------------------------------------------
            asld                            ;                               
            asld                            ; d =  d * 4                              
L1191       andm    injFlags0, #$7f         ; Reset startingToCrankColdEngine flag                                 
L1192       xgdx                            ; x = pulseWidth
                                                         
            ;-----------------------------------------------------
            ; Store injPwStart and update state3.7 from injFlags0.7
            ; (done this way since used in interrupts)
            ;-----------------------------------------------------
            ldaa    injFlags0               ;                               
            anda    #$80                    ; a = injFlags0 & $80, keep only that bit                             
            sei                             ;                              
            stx     injPwStart              ; injPwStart = pulseWidth
            ldab    state3                                                 
            andb    #$7f                    ;                             
            aba                             ; b = b&$7f + injFlags0&$80                             
            staa    state3                  ; Update state3
                 
            ;----------------------------------------                         
            ; Update state3 from state1
            ;----------------------------------------                         
            ldaa    state1                  ;                               
            anda    #$1b                    ; Keep 00011011
            brclr   state1, #$08, L1193     ; Branch if rotatingStopInj clear                                 
            brset   state1, #$04, L1193     ; Engine rotatingStopInj, branch if runningFast                                 
            oraa    #$20                    ; Engine rotatingStopInj but not runningFast, set bit                              
L1193       ldab    state3                  ;                              
            andb    #$c4                    ; Keep 11000100                             
            aba                             ;                             
            staa    state3                  ;                               

            ;--------------------------------------------------------------------------
            ; If engine is just startingToCrank and this is the first time we are here
            ; then compute sInjPw and schedule an interrupt to activate simultaneous 
            ; injection (if no injector is currently active)
            ;--------------------------------------------------------------------------
            cli                             ;                             
            brclr   state1, #$01, L1195     ; Bail if startingToCrank clear 
            brset   injFlags0, #$01, L1195  ; Engine startingToCrank, bail if injFlags0.0 already set, meaning we were already here before and                               
            orm     injFlags0, #$01         ; Set flag                                
            ldaa    #$0c                    ; a = $0c                            
            clrb                            ; d = $0c00                            
            sei                             ;                             
            std     sInjPw                  ; sInjPw = $0c00 = 3.072ms                              
            brset   injToAct, #$0f, L1194   ; Bail if any injector is active                                 
            ldd     t1t2_clk                ; No injector flag set, schedule interrupt
            addd    #$0014                  ; 20us                              
            std     t1_outCmpWr             ; schedule interrupt in 20us

            ;----------------------
            ; Compute accEnrFact
            ;----------------------
L1194       cli                             ;                             
L1195       ldx     #L2051                  ; x point to L2051                              
            jsr     interpEct               ; b = L2051(ect)                                 
            ldx     #t_accEnr1              ; x point to t_accEnr1                               
            ldy     #t_accEnr2a             ;                               
            addb    T2_crank                ;                             
            bcc     L1196                   ; branch if engine stopped "startingToCrank" more than L2051(ect)/2 sec ago.
            ldy     #t_accEnr2b             ;                               
L1196       jsr     L1577                   ;                              
            std     accEnrFact              ; [accEnrFact:accEnrFact+1] = 8 * injMasComp * t_accEnr1(rpm)/128 * [t_accEnr2a(ect) or t_accEnr2b(ect)]/128 * baroFact/128

            ;-----------------------
            ; Compute accEnrDecay 
            ;-----------------------
            ldx     #t_accEnrDecay          ;                               
            jsr     interpEct               ;                                  
            stab    accEnrDecay             ; accEnrDecay = t_accEnrDecay(ect)
                                                           
            ;---------------------
            ; Compute accEnrMinAf 
            ;---------------------
            ldx     #L2039                                                 
            jsr     interp16rpm             ; a = L2039(rpm)                                    
            ldab    #$57                    ;                              
            mul                             ; d = $57*L2039(rpm)                             
            jsr     scale16                 ; d = $57*L2039(rpm)/16                               
            std     accEnrMinAf             ; accEnrMinAf:L0106 = $57*L2039(rpm)/16                            

            ;---------------------
            ; Compute decEnrFact 
            ;---------------------          ;
            ldaa    T40_crank               ;                              
            adda    #$78                    ; 3s                            
            bcc     L1197                   ; branch if engine stopped "startingToCrank" more than 3s ago 
            clra                            ;                             
            clrb                            ;                             
            bra     L1199                   ;                              
L1197       ldx     #t_decEnr1              ;                                   
            ldy     #t_decEnr2              ;                                   
            jsr     L1577                   ;                              
L1199       std     decEnrFact              ; [decEnrFact:decEnrFact+1] = 8 * injMasComp * t_decEnr1(rpm)/128 * t_decEnr2/128 * baroFact/128

                                               
            ;-------------------------------------------------------------------------
            ; Compute sInjEnrInc   
            ; Parameters related to adding fuel during simultaneous injection mode
            ;-------------------------------------------------------------------------
            ldx     #L2051                  ; 
            jsr     interpEct               ; b = L2051(ect)                                
            ldx     #L2013                  ;                              
            addb    T2_crank                ; b = L2051(ect) + T2_crank                            
            bcc     L1202                   ; branch if engine stopped "startingToCrank" more than L2051(ect)/2 sec ago
            ldx     #L2050                  ; Overflow, change table                             
L1202       jsr     interpEct               ; b = L2050(ect) or L2013(ect)                                
            pshb                            ; st0 = L2050(ect) or L2013(ect)                            
            ldx     #L2015                  ;                              
            jsr     interp16rpm             ; b = L2015(rpm)                                   
            pula                            ; a = L2050(ect) or L2013(ect)                           
            aba                             ; a = L2050(ect) or L2013(ect) +  L2015(rpm)                           
            bcc     L1205                   ; Branch if no overflow                            
            ldaa    #$ff                    ; Overflow, use max                      
L1205       staa    sInjEnrInc              ; sInjEnrInc = L2050(ect) or L2013(ect) +  L2015(rpm)

            ;-------------------------------------------------------------------------
            ; Compute sInjEnrMax = sInjEnrInc/4   
            ; Parameters related to adding fuel during simultaneous injection mode
            ;-------------------------------------------------------------------------
            ldab    #$20                    ; b = $20                           
            mul                             ; d = $20 * sInjEnrInc
            jsr     scale128m               ; d = $20/128 * sInjEnrInc = 1/4 * sInjEnrInc, also check for max of 255...
            stab    sInjEnrMax              ; sInjEnrMax = 1/4 * sInjEnrInc = 1/4 * (L2051(ect) + T2_crank or L2050(ect) +  L2015(rpm))

            ;---------------------------------------------------------------------------------
            ; Compute sInjTpsMax, threshold used to increase fuel in simulateneous injection
            ;---------------------------------------------------------------------------------
            ldx     #t_sInjTpsMax           ;                              
            jsr     interp16rpm             ;                                   
            stab    sInjTpsMax              ; sInjTpsMax = t_sInjTpsMax(rpm)
                                                             
            ;---------------------------------
            ; Decrement T40s_casInt at 40Hz
            ;---------------------------------
            ldx     #T40s_casInt                                                 
            jsr     decX40Hz                ; Decrement T40s_casInt at 40Hz

            ;-------------------------------------------------------------------------
            ; Set the timing adjustment flag (timAdjFlags.7) if the timing 
            ; adjustment terminal is grounded but the ECU test mode terminal is not
            ;-------------------------------------------------------------------------
            brclr   port4Snap, #$10, L1209    ; Branch if stored timing terminal not grounded?                                   
            brclr   port4, #$10, L1209        ; Branch if timing terminal not grounded?                               
            brset   port4Snap, #$08, L1209    ; Branch if ECU test mode terminal grounded?                                   
            orm     timAdjFlags, #$80         ; Set flag, timing terminal grounded but ECU test mode terminal NOT grounded
            bra     L1210                     ; Bail                             
L1209       andm    timAdjFlags, #$7f         ; Reset flag       
                        
            ;-----------------------------------------------------
            ; Re-init knockTimer to $ff if engine notRotating  
            ;-----------------------------------------------------
L1210       brclr   state1, #$10, L1212       ; Branch if notRotating clear
            ldaa    #$ff                      ; Engine notRotating                             
            staa    knockTimer                                                 

            ;-----------------------------------------------------
            ; Update the "knock sensor bad" flag if 
            ; engine was started more than 1 sec ago
            ;-----------------------------------------------------
L1212       brset   state1, #$11, L1214       ; Branch if notRotating or startingToCrank
            ldaa    T40_crank                 ; Engine is running                              
            adda    #$28                      ; 
            bcs     L1214                     ; branch if engine stopped "startingToCrank" less than 1s ago (don't check knock sensor yet)
            orm     knockFlags, #$40          ; Set flag indicating "engine running for more than 1 sec"???                               
            brset   port4Snap, #$20, L1215    ; Branch if knock sensor is OK???                                   
            orm     state2, #$20              ; Set flag indicating knock sensor is bad                                
            bra     L1217                     ; Bail                             
L1214       andm    knockFlags, #$bf          ; Reset flag indicating "engine running for more than 1 sec"???                                
L1215       andm    state2, #$df              ; Reset bad knock sensor flag                                

            ;---------------------------------------------------------------------------------
            ; Update  knockFlags.7 (airVol threshold flag) and T200s_knock if below threshold  
            ;---------------------------------------------------------------------------------
L1217       ldab    airVol                    ; b=airVol
            cmpb    #$49                      ; 
            bcc     L1218                     ; branch if airVol>$49
            andm    T200s_knock, #$03         ; airVol<$49, reset T200s_knock to a more reasonable value
            andm    knockFlags, #$7f          ; clear knockFlags.7                                                                 
            bra     L1219                     ; branch LDB89                                                             
L1218       orm     knockFlags, #$80          ; set knockFlags.7                                                                   

            ;-----------------------------------------------------
            ; Something activated at 4595rpm with hysteresis??????
            ; Could be related to knock since we are in the area...
            ; Maybe knock sensor filter parameter being changed???
            ;-----------------------------------------------------
L1219       ldaa    #$96                      ; 4688rpm                                                                          
            brclr   port6, #$02, L1220        ; branch if ??? not yet activated???                                 
            ldaa    #$90                      ; 4500rpm                                                                          
L1220       cmpa    rpm31                     ;                                                                           
            bhi     L1221                     ;  Branch if rpm lower than threshold                                                                           
            orm     port6, #$02               ; rpm higher than threshold, Activate ???
            bra     L1222                     ;                                                                           
L1221       andm    port6, #$fd               ; De-activate ???

            ;----------------------------
            ; Section to update octane
            ;----------------------------
            ;--------------------------------------------------
            ; Skip octane update if temp(ectFiltered) < 80degC
            ;--------------------------------------------------
L1222       ldaa    ectFiltered                                                 
            cmpa    #$20                    ; 80degC                            
            bhi     L1227                   ; Bail if temp(ectFiltered) < 80degC                               

            ;-----------------------------------------
            ; temp(ectFiltered) >= 80degC
            ; Skip octane update under more cases... 
            ;-----------------------------------------
            brset   state2, #$28, L1227     ; Bail if no pulse accumulator interrupts or if knock sensor not working?
            brclr   knockFlags, #$40, L1227 ; Bail if engine has not been running for more than 1 sec                               
            ldy     #L2052                  ; Engine has been running for more than 1 sec                               
            jsr     rpmPwise                ; b = piecewise(rpm4) for table interpolation                                  
            ldaa    #$b0                    ; a = $b0                             
            jsr     abmin                   ; Apply max to b, b = min($b0,piecewise(rpm4))                             
            tba                             ; a = min($b0,piecewise(rpm4))                            
            ldx     #L2041                  ; x points to L2041                               
            jsr     interp16b               ; a = L2041(rpm4)                                  
            cmpa    airVol                  ;                                
            bcc     L1227                   ; Bail if airVol <= L2041(rpm4)                              

            ;---------------------------------------------
            ; airVol > L2041(rpm4), skip octane update 
            ; if 3<=knockSum<=5 (hysteresis zone...)
            ;---------------------------------------------
            ldaa    knockSum                ;                                 
            cmpa    #$03                    ;                             
            bcs     L1223                   ; Branch if knockSum <3                             
            cmpa    #$05                    ;                             
            bls     L1227                   ; Bail if knockSum <=5                             

            ;-------------------------------------------------------------
            ; knockSum<3 or knockSum>5, we can update octane at 2.5Hz
            ;-------------------------------------------------------------
L1223       rora                            ; shift in carry bit, rest of a = knockSum/2                            

            ;-----------------------------------------------------------
            ; Decrement T40s_octane at 40Hz (loops at $10)
            ; and update octane if timer is expired (at 2.5Hz)
            ;-----------------------------------------------------------
            brclr   Tclocks, #$01, L1227    ; Bail if 40Hz signal no set                                   
            ldab    T40s_octane             ; b = T40s_octane                             
            beq     L1224                   ; Branch if timer expired                             
            dec     T40s_octane             ; Update timer                             
            bne     L1227                   ; Bail if timer not yet expired

            ;-------------------------------------
            ; T40s_octane expired, update octane
            ;-------------------------------------
L1224       ldab    octane                  ; b = octane                               
            tsta                            ;                             
            bpl     L1225                   ; Branch if knockSum >=3 (see carry bit shited-in above)

            ;--------------------------------------------------
            ; knockSum <3, increment octane by 1 (max 255)
            ;--------------------------------------------------
            ldaa    #$10                    ; pre-load timer value                             
            incb                            ; b = octane+1                             
            bne     L1226                   ; Branf if no rollover                             
            decb                            ; Rollover, use max of 255                             
            bra     L1226                   ; Bail to store                             

            ;--------------------------------------------------
            ; knockSum >=3, decrement octane by 1 (min 0)
            ;--------------------------------------------------
L1225       ldaa    #$10                    ; pre-load timer value                             
            tstb                            ;                             
            beq     L1226                   ; Branch if octane already 0                             
            decb                            ; b = octane - 1                            
L1226       stab    octane                  ; update octane
            staa    T40s_octane             ; Re-init T40s_octane with $10                              

            ;-------------------------------------------------------------------------------------------------
            ; Section to compute timingOct, the timing interpolated from the 
            ; two timing maps (timing under high octane and low octane) according 
            ; to the current octane value
            ;
            ;       timingOct = alpha * t_timingHiOct(rpm, load) + (1-alpha) * t_timingLoOct(rpm, load)
            ;
            ; where alpha = octane/255, 0<= alpha <=1
            ;-------------------------------------------------------------------------------------------------
            ;-------------------------------------------------
            ; Compute rpm and load for 2D map interpolation                           
            ;-------------------------------------------------
L1227       ldy     #L2052                  ;
            jsr     rpmPwise                ; b = rpm                                
            stab    temp6                   ; temp6 = rpm                              
            jsr     getLoadForMaps          ; b = load                                      
            stab    temp7                   ; temp7 = load                             

            ;--------------------------------------
            ; Get timing value from t_timingHiOct
            ;--------------------------------------
            ldx     #t_timingHiOct          ; x points to t_timingHiOct                                  
            ldy     #$1000                  ;                               
            jsr     lookup2D                ; b = t_timingHiOct(rpm,load)
            stab    timFuelEnr              ; timFuelEnr = t_timingHiOct(rpm,load)

            ;------------------------------------------------------------------------------------
            ; Change load value for t_timingLoOct map interpolation (first three row missing)
            ;------------------------------------------------------------------------------------
            ldaa    temp7                   ; a = load                             
            suba    #$30                    ; a = load - $30                            
            bcs     L1229                   ; branch if load <$30 (no interpolation,  use t_timingHiOct(rpm,load)
            staa    temp7                   ; temp7 = load-$30                             

            ;------------------------------------------------------
            ; Compute t_timingHiOct(rpm,load) * octane and put it on stack
            ;------------------------------------------------------
            jsr     getOctane               ; a = validated octane                                   
            mul                             ; d = t_timingHiOct(rpm,load) * octane                             
            psha                            ; put on stack                             
            pshb                            ; put on stack
                                        
            ;-------------------------------------
            ; Get timing value from t_timingLoOct
            ;-------------------------------------
            ldx     #t_timingLoOct          ; x points to t_timingLoOct                                 
            ldy     #$1000                  ;                               
            jsr     lookup2D                ; b = t_timingLoOct(rpm, load)

            ;-----------------------------------------------------------------------------------------------------------
            ; Compute 
            ;       timingOct = octane/255 * t_timingHiOct(rpm,load) + (255 - octane)/255 * t_timingLoOct(rpm, load)
            ;                 = alpha * t_timingHiOct(rpm,load) + (1-alpha) * t_timingLoOct(rpm, load)
            ;-----------------------------------------------------------------------------------------------------------
            jsr     getOctane               ; a = octane                                   
            coma                            ; a = not(octane) = 255 - octane                             
            mul                             ; d = (255 - octane) * t_timingLoOct(rpm, load)
            std     temp6                   ; temp6:temp7 = (255 - octane) * t_timingLoOct(rpm, load)
            pulb                            ;                             
            pula                            ; d = octane * t_timingHiOct(rpm,load) 
            addd    temp6                   ; d = octane * t_timingHiOct(rpm,load) + (255 - octane) *  t_timingLoOct(rpm, load)
            div     #$ff                    ; a = remainder, b = octane/255 * t_timingHiOct(rpm,load) + (255 - octane)/255 *  t_timingLoOct(rpm, load)
            rola                            ; Put remainder high bit in carry
            adcb    #$00                    ; roundup b with remainder
L1229       stab    timingOct               ; timingOct = octane/255 * t_timingHiOct(rpm,load) + (255 - octane)/255 *  t_timingLoOct(rpm, load)
                          
            ;--------------------------------------------------------------------------------------------------
            ; Compute timFuelEnr = $4b/256 * ($b6/64 * (t_timingHiOct(rpm,load) - timingOct) + knockSum - 5)
            ; timFuelEnr is a fuel enrichment based on timing, octane and knockSum
            ;--------------------------------------------------------------------------------------------------
            ldaa    timFuelEnr              ; a = t_timingHiOct(rpm,load)
            suba    timingOct               ; a = t_timingHiOct(rpm,load) - timingOct
            bcc     L1230                   ; Branch if result positive                              
            clra                            ; Use min of 0                            
L1230       ldab    #$b6                    ; b = $b6                            
            mul                             ; d = $b6 * (t_timingHiOct(rpm,load) - timingOct)
            jsr     scale64                 ; b = $b6/64 * (t_timingHiOct(rpm,load) - timingOct)
            addb    knockSum                ; b = $b6/64 * (t_timingHiOct(rpm,load) - timingOct) + knockSum 
            bcc     L1232                   ; Branch if no overflow                             
            ldab    #$ff                    ; Overflow, use max of 255                            
L1232       subb    #$05                    ; b = $b6/64 * (t_timingHiOct(rpm,load) - timingOct) + knockSum - 5                            
            bcc     L1233                   ; Branch if result positive                             
            clrb                            ; Use min of 0                            
#ifdef E931                                 
L1233       ldaa    #$4b                    ; a = $4b                            
#else                                       
L1233       ldaa    #$86                    ; a = $86                            
#endif                                      
            mul                             ; d =  $4b*($b6/64 * (t_timingHiOct(rpm,load) - timingOct) + knockSum - 5)                            
            staa    timFuelEnr              ; timFuelEnr = $4b/256 * ($b6/64 * (t_timingHiOct(rpm,load) - timingOct) + knockSum - 5)                                 

            ;---------------------------------------
            ; Section to update maxAdv for E931
            ;---------------------------------------
#ifdef E931
            brset   state1, #$04, Mdc7a     ; Branch if engine runningFast                                 
            brset   state1, #$10, Mdc76     ; Branch if notRotating
            ldaa    rpm8                    ; 
            cmpa    t_idleSpd               ;                                   
            bcs     Mdc76                   ; Branch if rpm8 < t_idleSpd (normal idle speed)                             
            ldaa    tpsDiffMax2             ; 
            cmpa    #$03                    ;                              
            bcc     Mdc76                   ; Branch if tpsDiffMax2 >= 3 (pedal is moving forward...)
            ldaa    airDiffPos1             ;                                     
            cmpa    #$0a                    ;                              
            bcs     L1234                   ; Bail (dont even update maxAdv) if airDiffPos1 < $0a (airflow decrease or small airflow increase)
                                                         
            ;----------------------------------------
            ; Use max of $80 (maxAdv=$80, no limit?)  
            ; if notRotating
            ;    or rpm8 < t_idleSpd
            ;    or tpsDiffMax2 >= 3
            ;    or airDiffPos1 >= $0a
            ;----------------------------------------
Mdc76       ldaa    #$80                    ; Use default of $80 (no limit)                              
            bra     Mdc90                   ; Branch to store
                                           
            ;--------------------------------------------------------------------
            ; Engine runningFast, compute maxAdv which will reduce the 
            ; timing advance by 13deg or limit it to 12deg
            ;---------------------------------------------------------------------
Mdc7a       ldaa    vssCnt1                 ;                                 
            beq     L1234                   ; Bail if car not moving                               
            ldaa    #$05                    ;                              
            staa    T_maxAdv                ; Init timer T_maxAdv = 5 ?
            ldaa    timingOct               ;                                   
            suba    #$0d                    ;                             
            bcc     Mdc8a                   ; Branch if timingOct - $0d positive                              
            clra                            ; Use min of 0                             
Mdc8a       ldab    #$12                    ; b = $12                             
            cba                             ;                              
            bcc     Mdc90                   ; Branch if timingOct-$0d >= $12                              
            tba                             ; Use max of $12 degrees                             
Mdc90       staa    maxAdv                  ; maxAdv = max(timingOct - $0d, 12)                                
#endif

            ;-------------------------------------------------
            ; Set timAdjFlags.1 flag if rpm>2000rpm or reset it
            ;-------------------------------------------------
L1234       ldab    #$40                     ; assume b = threshold = 2000rpm                           
            brclr   timAdjFlags, #$01, L1235 ; Branch if flag clear                              
            ldab    #$3a                     ; Flag was previously set, use a lower threshold of 1813rpm (hysteresis)                             
L1235       andm    timAdjFlags, #$fe        ; Reset flag                               
            cmpb    rpm31                    ;                              
            bcc     L1237                    ; Branch if rpm31 <= threshold (2000rpm or 1813rpm)
            orm     timAdjFlags, #$01        ; rpm31 > threshold, set flag                              

            ;------------------------------------------------------------------------
            ; Compute advRpm under some conditions (low rpm, idle switch off, etc.)
            ; advRpm is an rpm based timing advance/retard with +/-8deg max
            ;------------------------------------------------------------------------
L1237       ldaa    #$80                     ; preload a = $80 = default value (no timing change)                             
            brset   timAdjFlags, #$01, L1243 ; Bail if rpm31 > 2000rpm (with hysteresis)                              
            brset   iscFlags0, #$04, L1243   ; Bail if basic idle speed adjustment mode is active (no timing change)                              
            brset   state1, #$19, L1243      ; Bail if notRotating or startingToCrank or rotatingStopInj
            brclr   port3Snap0, #$80, L1243  ; Bail if idle switch on                                   
            ldab    vssCnt1                 ;                                
            brn     L1243                   ; Branch never (?)                              
            ldx     #$0000                  ; x = 0                              
            clrb                            ; b = 0                            
            ldaa    idleSpdTarg             ; d = 256*idleSpdTarg                             
#ifdef E931                                 ;
            suba    #$06                    ; d = 256*(idleSpdTarg - 6)      (-47rpm)                   
#else                                       ;
            suba    #$04                    ;                             
#endif                                      ;
            bcc     L1238                   ; Branch if no underflow                              
            clra                            ; Underflow, use min of 0                            
L1238       jsr     scale8                  ; a = 256/8 * (idleSpdTarg - 6) = 32*(idleSpdTarg - 6)                              
            cmpd    rpmX4Filt               ;                                 
            bcc     L1239                   ; Branch if 32*(idleSpdTarg - 6) >= rpmX4Filt                             
            ldd     rpmX4Filt               ; use min of rpmX4Filt                                 
L1239       jsr     scale16                 ; d = 2*(idleSpdTarg - 6)
            subd    rpm4                    ; d = 2*(idleSpdTarg - 6) - rpm4 
            bcc     L1240                   ; Branch if positive                             
            inx                             ; result negative, x = 1                            
            coma                            ;                             
            comb                            ;                             
            addd    #$0001                  ; d =  rpm4 - 2*(idleSpdTarg - 6)
L1240       jsr     ovfCheck                ; b = result = abs(rpm4 - 2*(idleSpdTarg - 6))
            ldaa    #$68                    ; a = $68                            
            mul                             ; d = $68 * abs(rpm4 - 2*(idleSpdTarg - 6))
            jsr     round256                ; a = $68/256 * abs(rpm4 - 2*(idleSpdTarg - 6))
            cmpa    #$08                    ;                             
            bls     L1241                   ; Branch if a <= 8 (+/-8 degrees advance or retard)
            ldaa    #$08                    ; Use max of 8                            
L1241       dex                             ; x = x-1                            
            bne     L1242                   ; Branch if we did not have a negative result earlier                            
            nega                            ; Result was negative, negate again to restore it...                             
L1242       adda    #$80                    ; a =  $80 + $68/256 * (rpm4 - 2*(idleSpdTarg - 6))
L1243       staa    advRpm                  ; advRpm = $80 + $68/256 * (rpm4 - 2*(idleSpdTarg - 6))

            ;--------------------------------------------------
            ; Compute advEct, ect based timing advance/retard
            ;--------------------------------------------------
            ldx     #L2020                                                 
            jsr     interpEct                                                 
            stab    advEct                  ; advEct = L2020(ect)                              

            ;---------------------------------------------------------------
            ; Compute advIat iat based advance/retard under low load
            ;---------------------------------------------------------------
            ldx     #L2038                  ;                               
            jsr     interp16rpm             ; b = L2038(rpm)                                    
            cmpa    airVolB                 ;                                
            bls     L1244                   ; Branch if L2038(rpm) <= airVolB                             
            ldaa    #$80                    ; Use default value of $80 under high load                            
            bra     L1245                   ;                              
L1244       ldx     #L2021                  ; L2038(rpm) <= airVolB                              
            jsr     iatCInterp              ;                                   
L1245       staa    advIat                  ; advIat = L2021(iat)

            ;----------------------------------------------------------------------------------
            ; Compute advTotal = min(timingOct, maxAdv) + advEct  + advIat + advRpm - $0180
            ;                  = min(timingOct, maxAdv) + (advEct-$80)  + (advIat-$80) + (advRpm-$80)
            ;----------------------------------------------------------------------------------
            ldx     #advTotal               ; x points to advTotal (table of timing related value)                             
            ldab    $01,x                   ; b = timingOct (timing corrected for current octane)                               
#ifdef E931
            cmpb    maxAdv                  ;                               
            bls     L1246                   ; branch if timingOct<=maxAdv                               
            ldab    maxAdv                  ; Use max of maxAdv                                
#endif
L1246       clra                            ; d = min(timingOct, maxAdv) (a = 0...)                            
            xgdy                            ; y =  min(timingOct, maxAdv)                            
            ldab    $02,x                   ; b = advEct                              
            aby                             ; y = min(timingOct, maxAdv) + advEct                            
            ldab    $03,x                   ; b = advIat                             
            aby                             ; y = min(timingOct, maxAdv) + advEct  + advIat                             
            ldab    $04,x                   ; b = advRpm
            aby                             ; y = min(timingOct, maxAdv) + advEct  + advIat + advRpm
            xgdy                            ; d = min(timingOct, maxAdv) + advEct  + advIat + advRpm
            cmpd    #$01bc                  ;                               
            bls     L1247                   ; Branch if min(timingOct, maxAdv) + advEct  + advIat + advRpm <= $01bc
            ldd     #$01bc                  ; Use max of $01bc
                                          
L1247       cmpd    #$0180                  ;                               
            bcc     L1248                   ; Branch if min(timingOct, maxAdv) + advEct  + advIat + advRpm >= $0180
            ldd     #$0180                  ; Use min of $0180
                                          
L1248       subd    #$0180                  ; d = min(timingOct, maxAdv) + advEct  + advIat + advRpm - $0180
            stab    $00,x                   ; advTotal = min(timingOct, maxAdv) + advEct  + advIat + advRpm - $0180

            ;----------------------------------------------------------
            ; Compute tim61Tot0 = $e7 - $b6/64 * (advTotal + $0a) 
            ;                   = 256 * (61deg - (advTotal-10deg)) / 90
            ;
            ; This is timing referenced to -61deg BTDC
            ; -10deg is because advTotal is shifted by 10deg (timingOct 
            ; is from the timing maps which are shifted by 10 deg...)
            ;----------------------------------------------------------
            addb    #$0a                    ; b = advTotal + $0a
            ldaa    #$b6                    ; a = $b6                             
            mul                             ; d = $b6 * (advTotal + $0a)                            
            jsr     scale64                 ; d = $b6/64 *  (advTotal + $0a)
            ldaa    #$e7                    ; a = $e7                            
            sba                             ; a = $e7 - $b6/64 *  (advTotal + $0a)
            staa    tim61Tot0               ; tim61Tot0 = $e7 - $b6/64 *  (advTotal + $0a)

            ;-------------------------------
            ; Compute timingAdv from tim61
            ;-------------------------------
            ldaa    #$a0                    ; a = $a0 (default when engine not running)                           
            brset   state1, #$11, L1249     ; Branch if notRotating or startingToCrank
            ldaa    tim61                   ; a = tim61                             
L1249       ldab    #$5a                    ; b = $5a                            
            mul                             ; d = $5a * tim61
            jsr     round256                ; a = $5a * tim61/256
            nega                            ; a = -($5a * tim61/256)
            adda    #$47                    ; a = -($5a * tim61/256) + $47 = $47 - $5a * tim61/256 
            staa    timingAdv               ; timingAdv = $147 - $5a * tim61/256

            ;-------------------
            ; Compute enerLen
            ;-------------------
            ldaa    battRaw                 ;                                
            suba    #$80                    ; a = battRaw - $80  (9.38v)                          
            bcc     L1250                   ; branch if underflow                              
            clra                            ; Use min of 0                            
L1250       staa    temp5                   ; temp5 = max(0,battRaw - $80)                             
            ldx     #t_enerLen              ; x points to t_enerLen                               
            jsr     interp16b               ; b = t_enerLen(battRaw)                                 
            stab    enerLen                 ; enerLen = t_enerLen(battRaw)                             

            ;-------------------------------------------------
            ; Update coilChkFlags.5 flag, Set bit if engine 
            ; running and rpm<5000 and 8V<=battRaw<=18V
            ;-------------------------------------------------
            brset   state1, #$11, L1253     ; Branch if notRotating or startingToCrank 
            ldaa    rpm31                   ; a = rpm31                              
            cmpa    #$a0                    ;                             
            bcc     L1253                   ; Branch if rpm31 >= 5000rpm                             
            ldaa    battRaw                 ; a = battRaw                               
            cmpa    #$f5                    ; 18V                             
            bhi     L1253                   ; Branch if battRaw > 18V                              
            cmpa    #$6d                    ; 8V                             
            bcs     L1253                   ; Branch if battRaw < 8V                              
            orm     coilChkFlags, #$20      ; At this point voltage is between 8V and 18V, set bit
            bra     L1255                   ;                              
L1253       andm    coilChkFlags, #$df      ; Reset bit 

            ;------
            ; Exit
            ;------
L1255       rts                             ;                             



;******************************************************************
;
; Return the octane value if sensors look ok, 0 otherwise 
; (very low octane to be on the safe side)
;
;
;
;******************************************************************
getOctane   clra                                                         
            brset   state2, #$28, L1257     ; Branch if no pulse accumulator interrupts or knock sensor not working 
            ldaa    octane                                                 
L1257       rts                                                          



;******************************************************************
;
;
; Third subroutine
;
;
;******************************************************************
            ;-------------------------------------------
            ; Update fuel pump activation/deactivation
            ;-------------------------------------------
subroutine3 brclr   state1, #$10, L1259     ; Branch if notRotating clear
            brset   obdActCmd, #$02, L1259  ; Engine notRotating, branch if fuel pump is being actuated through OBD command
            orm     port1, #$10             ; De-activate fuel pump relay
            bra     L1260                   ; Bail                                                                                          
L1259       andm    port1, #$ef             ; activate fuel pump relay

            ;------------------------------------------------------------------------
            ; Re-init T40_acOn if A/C switch on is off
            ; (implement a min delay before turning A/C on after button is pressed)
            ;------------------------------------------------------------------------
L1260       ldx     #T40_acOn                ; X points to 40Hz timer T40_acOn                                                                                           
            brclr   port3Snap0, #$10, L1261  ; Branch if A/C switch flag off (switch is on?)                                                                                         
            ldaa    #$18                     ; Switch is off, init timer                                                                                        
            staa    $00,x                    ; Re-init T40_acOn with $18 (0.6s, min time before activating A/C)                                                                                         

            ;---------------------------------------------------------------------------------
            ; Re-init T40_acOnRpm if rpm<438
            ; (implement a min delay before turning A/C on after RPM > 438 (after start-up)
            ;---------------------------------------------------------------------------------
L1261       ldaa    rpm31                   ; a = rpm                                                                               
            cmpa    #$0e                    ; 438rpm                                                                                
            bhi     L1262                   ; Branch if rpm > 438                                                                   
            ldaa    #$20                    ; rpm lower than 438, init timer
            staa    $01,x                   ; rpm<438 -> Re-init timer #T40_acOnRpm with $20 (0.8s)
                              
            ;--------------------------------------------------------------
            ; For AT, decide if we will turn A/C on/off based on TPS...
            ;--------------------------------------------------------------
L1262       .equ    $                       ;
#ifdef E932    
            ;-----------------------------------------------------------------
            ; Load TPS value of 78% or 82% (80% target with +/-2% hysteresis) 
            ;-----------------------------------------------------------------
            ldaa    #$d2                    ; Load 82% threshold                            
            brclr   varFlags0, #$01, L1263  ; Do not branch if TPS was higher than 82% the previous time we were here                             
            ldaa    #$c7                    ; Use 78% threshold instead (hysteresis)              
            
            ;-----------------------------------------------------------------
            ; Check if TPS is above/below threshold and set varFlags0 accordingly
            ;-----------------------------------------------------------------
L1263       orm     varFlags0, #$01         ; Assume this bit will be set (reset below)                               
            cmpa    tpsRaw                  ;                            
            bls     L1264                   ; Branch if threshold smaller than TPS (TPS higher than threshold)

            ;----------------------------------------------------------------------------------
            ; TPS lower than threshold, reset varFlags0.0 flag and set timer T40_acCut to 5s
            ;----------------------------------------------------------------------------------
            andm    varFlags0, #$fe         ; TPS lower than threshold, reset varFlags0.0                               
            ldaa    #$c8                    ; 5s at 40Hz                            
            staa    $02,x                   ; Init T40_acCut to 5s (delay before turning A/C back on)                             
#endif

            ;---------------------------------------------------------------------------
            ; Make sure both T40_acOn and T40_acOnRpm are 0 before attempting to turn A/C on
            ; Implement a min delay before engaging A/C 
            ; clutch once car has started or A/C button is pressed
            ;---------------------------------------------------------------------------
L1264       ldaa    $00,x                   ; a = T40_acOn
            oraa    $01,x                   ; a = T40_acOn | T40_acOnRpm                                                  
            bne     L1266                   ; Branch if at least one timert not yet 0 (turn A/C off)                                       
            
            ;-----------------------------------------------------------------------------
            ; At this point, both T40_acOn and T40_acOnRpm timers are at 0, we can turn A/C on
            ;-----------------------------------------------------------------------------
#ifdef E932
            ;--------------------------------------------------------------
            ; For AT, decide if we will turn A/C on/off based on TPS...
            ; Seems A/C is cutoff for a maximum of 5 seconds when TPS>80%
            ; but it is turned back on whenever TPS goes below 80% (no delay)
            ; It would probably be better to turn-it off for 5s anyway...
            ;--------------------------------------------------------------
            brclr   varFlags0, #$01, L1265  ; Branch if TPS was lower than threshold (turn it back on immediately, not the best????)
            brset   port3Snap0, #$20, L1265 ; TPS is higher than threshold, branch if Park/neutral flag is set (no need to cutoff if in park)
            ldaa    $02,x                   ; Get T40_acCut value to see if we can turn A/C back on (5 second delay)                              
            bne     L1266                   ; Branch if timer not expired                            
#endif

            ;----------------
            ; Turn A/C on 
            ;----------------
L1265       andm    port1, #$df             ; Turn A/C clutch bit to 0 
            bra     L1267    
                                                                                      
            ;----------------
            ; Turn A/C off
            ;----------------
L1266       orm     port1, #$20             ; Turn A/C clutch bit to 1 

            ;--------------------------------------------------------------
            ; Section to update the purge solenoid activation/deactivation
            ;--------------------------------------------------------------
            ;------------------------------------------------------------
            ; Reset forced activation and forced deactivation flags 
            ; since we are going to update them
            ;------------------------------------------------------------
L1267       andm    varFlags0, #$9f         ; Reset bits 01100000 ($20 and $40)

            ;-----------------------------------
            ; Branch according to engine state
            ;-----------------------------------
            brclr   state1, #$10, L1270     ; Branch if notRotating clear

            ;-----------------------------------------------------------
            ; Engine notRotating, check if an OBD command is ongoing
            ; to activate solenoid, set flags in consequence
            ;-----------------------------------------------------------
            brset   obdActCmd, #$01, L1269  ; Branch if purge solenoid is actuated by OBD
            orm     varFlags0, #$20         ; Set "forced deactivation flag" 
            bra     L1276                   ; Branch to continue                             
L1269       orm     varFlags0, #$40         ; Set "forced activation" flag
            bra     L1276                   ; Branch to reset pulsewidth modulation flag since engine not rotating...  
                                        
            ;----------------------------------------------------------------
            ; Engine rotating
            ; Check if minimum conditions are met to activate purge solenoid
            ;----------------------------------------------------------------
L1270       ldaa    T2_crank                ; a = T2_crank                                 
            adda    #$78                    ;                             
            bcs     L1271                   ; Branch if engine stopped "startingToCrank" less than 60 sec ago.
            brclr   ftrimFlags, #$03, L1271 ; Branch if current trim range is "low"                                    
            ldaa    ectFiltered             ; a = ectFiltered                                    
            cmpa    #$2d                    ; 66degC                            
            bls     L1272                   ; Branch if temperature(ectFiltered) >= 66degC                             

            ;-----------------------------------------------------------
            ; Conditions are not good to activate purge solenoid
            ; Set "forced deactivation" flag
            ;-----------------------------------------------------------
L1271       orm     varFlags0, #$20         ; Set flag                               
            bra     L1274                   ; Branch to continue        
                                 
            ;---------------------------------------------------------------
            ; Minimum condition for activation are met, check if there are
            ; special conditions where we should always activate???
            ;---------------------------------------------------------------
L1272       brclr   state1, #$80, L1273     ; Branch to activate if open loop mode is active
            
            ;------------------------------
            ; We are in closed loop mode
            ;------------------------------
            ldaa    baroChecked             ; a = baroChecked
            cmpa    #$9c                    ; 1 bar                            
            bcs     L1273                   ; Branch to activate if baroChecked < 0.76 bar, activate if baro is very low?                             
            ldaa    iatChecked              ; a = iatChecked                                  
            cmpa    #$49                    ; 50degC                            
            bhi     L1274                   ; Branch if temperature(iatChecked) < 50degC                              

            ;--------------------------------------------------------------------------------
            ; At this point, min conditions are met and either
            ;   open loop mode is active 
            ; or 
            ;   closed loop mode is active  and (baroChecked < 0.76 or temperature(iatChecked) >= 50degC)
            ;
            ; Set "forced activation" flag indicating 
            ; we should activate purge solenoid 
            ;--------------------------------------------------------------------------------
L1273       orm     varFlags0, #$40         ; Set flag                                

            ;----------------------------------------------------------------
            ; Continuation from code flows above when engine is rotating...
            ; Update varFlags0.7 deactivation flag if its timer is expired
            ;
            ; varFlags0.7 deactivation flag is used to activate/deactivate 
            ; solenoid when none of the other two flags are set. Flag 
            ; stays set for 24sec and stays reset for 212 sec. Toggled 
            ; between the two states, basically implementing pulsewidth 
            ; modulation with a very long period...
            ;----------------------------------------------------------------
L1274       ldaa    T0p5_purge              ; a = T0p5_purge                                  
            bne     L1278                   ; Bail to activate/deactivate if timer not expired                             

            ;-----------------------------------------------------------------
            ; Timer is expired, time to toggle the flag, 
            ; branch to appropriate section depending on current flag value
            ;-----------------------------------------------------------------
            brset   varFlags0, #$80, L1275  ; Branch if deactivation flag was set previously

            ;-----------------------------------------------------------------------
            ; Flag is not set, first check if "forced activation" is requested
            ; in that case we just bail since it doesn't matter anymore...
            ;-----------------------------------------------------------------------
            brset   varFlags0, #$40, L1278  ; Bail to activate if solenoid needs "forced activation"                              

            ;-----------------------------------------------------------------------
            ; Time has come to toggle the flag to 1 and reset the timer to 24sec
            ;-----------------------------------------------------------------------
            ldaa    #$0c                    ; a = 24s                            
            orm     varFlags0, #$80         ; Set flag                               
            bra     L1277                   ; Branch to update timer and activate/deactivate    

            ;-----------------------------------------------------------------------
            ; Flag is set, first check if "forced deactivation" is requested
            ; in that case we just bail since it doesn't matter anymore...
            ;-----------------------------------------------------------------------
L1275       brset   varFlags0, #$20, L1278  ; Bail to activate/deactivate if "forced deactivation" flag is set                              

            ;-----------------------------------------------------------------------
            ; Time has come to toggle the flag to 0 and reset the timer to 212sec
            ;-----------------------------------------------------------------------
L1276       ldaa    #$6a                    ; 212s
            andm    varFlags0, #$7f         ; Reset flag                               
L1277       staa    T0p5_purge              ; T0p5_purge = 212sec         
                      
            ;------------------------------------------------------------------
            ; Continuation from all code flows above...
            ; Based on flags, decide to activate or deactivate purge solenoid
            ; Flags are tested in priority order...
            ;------------------------------------------------------------------
L1278       brset   varFlags0, #$40, L1279      ; 1st priority, branch to activate if forced activation is set
            brset   varFlags0, #$20, L1280      ; 2nd priority, branch to deactivate if forced deactivation is set                              
            brset   varFlags0, #$80, L1280      ; 3rd priority, branch to deactivate if pulswidth modulation flag is set                              

            ;---------------------------
            ; Activate purge solenoid
            ;---------------------------
L1279       andm    port6, #$ef             ; Activate purge solenoid
            bra     L1281                   ;                              

            ;----------------------------
            ; Deactivate purge solenoid
            ;----------------------------
L1280       orm     port6, #$10             ; Deactivate purge solenoid


            ;--------------------------------------------------------------
            ; Section to update the EGR solenoid activation/deactivation
            ;--------------------------------------------------------------
            ;----------------------------------------------------------------
            ; Compute egr duty cycle factor 
            ; as a function of rpm and airVol from 2D table t_egrDutyFact 
            ;----------------------------------------------------------------
L1281       ldab    rpmIndex1               ;                              
            ldaa    #$70                    ; max of rpm                            
            jsr     abmin                   ; b = max(rpmIndex1, $70)                             
            stab    temp6                   ; column index is rpm                             
            ldab    airVol                  ;                               
            ldaa    #$80                    ; max of airVol
            jsr     rpmRange                ;                                 
            stab    temp7                   ; row index is airVol                        
            ldab    #$80                    ; b = 100% duty cycle                            
            brclr   state1, #$10, L1282     ; Branch if notRotating clear
            brset   obdActCmd, #$08, L1283  ; Engine notRotating, branch if EGR solenoid actuated (by OBD) -> use 100% duty
L1282       clrb                            ; b = 0% duty cycle                           
            brset   state2, #$08, L1283     ; Branch if no pulse accumulator interrupts  -> use 0% duty cycle                                
            brset   state1, #$11, L1283     ; Branch if notRotating or startingToCrank -> use 0% duty cycle
            ldx     #t_egrDutyFact          ;                               
            ldy     #$0800                  ;                               
            jsr     lookup2D                ; b = t_egrDutyFact(rpm, airVol)                                 
            clra                            ;                             
            std     temp6                   ; temp6:temp7 = t_egrDutyFact(rpm,airVol)                              

            ;---------------------------------------------------------------------------------
            ; Get EGR solenoid duty cycle from t_egrDuty and apply factor from above
            ;---------------------------------------------------------------------------------
            ldx     #t_egrDuty              ;                                   
            ldaa    ectCond                 ;                                
            jsr     interp32mul             ; b = t_egrDutyFact(rpm,airVol) * t_egrDuty(ect)                                   
L1283       stab    egrDuty128              ; egrDuty128 = t_egrDutyFact(rpm,airVol) * t_egrDuty(ect) with $80=100%                                   
            
            ;-------------------------------------
            ; Scale duty factor to 00 - $30 range
            ;-------------------------------------
            ldaa    #$30                    ; 
            mul                             ;                             
            jsr     scale128                ; b = $30 * egrDuty128/128                              
            stab    egrDuty                 ; egrDuty with max of $30=100%

            ;--------------------------------------------------------------------
            ; Re-Init T2_EcuPower to $ff if T40_noPower expired
            ; (T2_EcuPower will start counting from $ff when power is back on...
            ;--------------------------------------------------------------------
            ldaa    T40_noPower             ;                                    
            bne     L1284                   ; Branch if ECU still has power                             
            ldaa    #$ff                    ; ECU about to loose power, reset T2_EcuPower to max (127.5sec)                               
            staa    T2_EcuPower             ;
                                                    
            ;-----------------------------------------------------------
            ; Section to update boost control solenoid duty cycle
            ;-----------------------------------------------------------
            ;-----------------------------------------------------------
            ; Check if time has come, section is updated at ~40Hz
            ;-----------------------------------------------------------
L1284       brclr   Tclocks, #$01, L1298    ; Bail of section if 40Hz signal no set                                   
            ldab    fpsBcsFlags             ; b = old fpsBcsFlags                              
            andm    fpsBcsFlags, #$8f       ; Assume those three flags are reset, updated below (0111 0000)

            ;-------------------------------------------------------------------
            ; Check if octane is above/below threshold with hysteresis 
            ; (high $c0, low $9a) and update fpsBcsFlags.5 flag (reset above) 
            ;-------------------------------------------------------------------
            ldaa    #$9a                    ; start with low threshold, a = $9a
            bitb    #$20                    ; test bit                                                                   
            bne     L1285                   ; Branch if old fpsBcsFlags.5 was set                                     
            ldaa    #$c0                    ; bit was not set, use higher threshold a = $c0
L1285       cmpa    octane                  ; 
            bcc     L1286                   ; Branch if octane <= threshold
            orm     fpsBcsFlags, #$20       ; set flag since we are above threshold 

            ;-------------------------------------------------------------------
            ; Check if mafRaw16 is above/below threshold with hysteresis 
            ; (high $4e, low $38) and update fpsBcsFlags.4 flag (reset above) 
            ;-------------------------------------------------------------------
L1286       ldaa    #$38                    ; a = #0038                                                        
            bitb    #$10                    ;                                                                  
            bne     L1287                   ; Branch if old fpsBcsFlags.4 was set  
#ifdef E931                                  
            ldaa    #$4e                    ; a = #004e
#else
            ldaa    #$4a                    ;                             
#endif
L1287       cmpa    mafRaw16                ; 
            bcc     L1288                   ; branch if mafRaw16 <= threshold
            orm     fpsBcsFlags, #$10       ; set flag since we are above threshold 


            ;-------------------------------------------------
            ; Branch to proper section if engine not running
            ;-------------------------------------------------
L1288       brclr   state1, #$10, L1289     ; Branch if notRotating clear 
            brset   obdActCmd, #$20, L1295  ; Engine notRotating, branch if boost solenoid actuated (by OBD command I assume)
L1289       brset   state1, #$11, L1293     ; branch if notRotating or startingToCrank

            ;----------------------------------------------------
            ; Engine is running...
            ; Check if time has come to update
            ;----------------------------------------------------
            ldaa    T40s_bcs                ; 
            bne     L1297                   ; Branch if timer not expired                             

            ;----------------------------------------------------
            ; Timer expired, time to update has come (~2Hz)
            ;
            ; By default, increase bcsDuty by 8 and test if we
            ; should not reduce it instead
            ;----------------------------------------------------
            ldab    bcsDuty                  ; b = bcsDuty
            addb    #$08                     ; b = bcsDuty + 8
            brset   state2, #$28, L1292      ; Branch if no pulse accumulator interrupts being received or knock sensor not working
            brset   fpsBcsFlags, #$10, L1292 ; Branch if mafRaw16 above threshold 
            brset   fpsBcsFlags, #$20, L1294 ; Branch if octane above threshold 

            ;--------------------------------------------------------------
            ; At this point, knock sensor is not working or we are not
            ; receiving airflow sensor interrupts or mafRaw16 is above
            ; threshold or octane is below threshold, basically these
            ; are onditions where we would want to reduce turbo pressure 
            ;
            ; Reduce bcsDuty by 2 instead of increasing by 8 
            ;--------------------------------------------------------------
L1292       subb    #$10                     ; b = bcsDuty + 8 - 10 = bcsDuty - 2
            bcc     L1294                    ; Branch if no underflow                             
L1293       clrb                             ; Use min of 0                            

            ;---------------------------------------
            ; Check new bcsDuty for max of $30, 
            ; store new value and update the timer
            ;---------------------------------------
L1294       cmpb    #$30                     ;                             
            bcs     L1296                    ; Branch if new bcsDuty < $30                               
L1295       ldab    #$30                     ; Use max of $30
L1296       stab    bcsDuty                  ; Store new bcsDuty
            ldaa    #$14                     ; Re-init timer to 20 (0.5sec)                            
L1297       deca                             ; Decrement timer                            
            staa    T40s_bcs                 ; Store updated timer                             


            ;-------------------------------------
            ; Decrement T40s_tps at 40Hz
            ;-------------------------------------
L1298       sei                             ;                             
            ldx     #T40s_tps               ;                               
            jsr     decX40Hz                ; Decrement T40s_tps at 40Hz 
            cli                             ;                             

            ;------------------------------------
            ; Compute the boost gauge duty cycle 
            ; depending on current conditions
            ;------------------------------------
            clrb                            ; load default duty cycle of b = 0                             
            ldaa    T40_noPower             ;                               
            beq     L1299                   ; Bail if timer expired (ECU is about to shut-down...) (use 0 duty)                              
            ldab    #$0c                    ; Load default duty cycle of b = $0c
            brset   state1, #$10, L1299     ; Bail if notRotating (use half duty...)
            clrb                            ; load default duty cycle of b = 0 
            brset   state2, #$08, L1299     ; Bail if no pulse accumulator interrupts (use 0 duty)                               
            ldx     #t_bGauge               ; x points to boost gauge table                              
            ldaa    airVolT                 ; a = airVolT                                
#ifdef batteryGauge
            jsr     battGauge               ;
#else
            jsr     interp32                ; b = t_bGauge(airVolT) (max value is $18...)                                
#endif
            ;-------------------------------------------------
            ; Update bGaugeODuty with $18-dutyCycle (min of 0)
            ; bGaugeODuty is the off-duty cycle... 
            ;-------------------------------------------------
L1299       ldaa    #$18                    ; a = $18                              
            sba                             ; a = $18-t_bGauge(airVolT)                              
            bcc     L1300                   ; Branch if no underflow                              
            clra                            ; underflow, use min                             
L1300       staa    bGaugeODuty             ; Update boost gauge off-duty cycle                                  

            ;----------------------------------------------
            ; Section to update the fuel pressure solenoid
            ;----------------------------------------------
            ;-----------------------------------------------------
            ; First check if there are any reason to activate it
            ;-----------------------------------------------------
            ldab    fpsBcsFlags              ; b = old fpsBcsFlags, used later...                         
            andm    fpsBcsFlags, #$fb        ; Reset bit indicating solenoid was just deactivated will be updated below if required                          
            brclr   state1, #$11, L1302      ; branch if notRotating and startingToCrank clear   
            andm    fpsBcsFlags, #$f7        ; engine is either notRotating or startingToCrank                               
            brclr   state1, #$10, L1301      ; Branch if notRotating clear (startingToCrank is set...)                           
            brset   obdActCmd, #$04, L1306   ; branch to activate solenoid if OBD command activated
            bra     L1307                    ; No reason to activate it, branch to deactivate solenoid                         

            ;-----------------------------------------------------------------
            ; Engine is startingToCrank, check if we should set fpsBcsFlags.3 flag (vapor lock)
            ; Basically set the flag when vapor lock conditions exists
            ;-----------------------------------------------------------------
L1301       ldaa    iatChecked               ;                               
            cmpa    #$9d                     ;                         
            bhi     L1302                    ; Branch if temperature(iatChecked) < 10degC                         
            ldaa    ectFiltered              ;                                
            cmpa    #$27                     ; 72degC                         
            bhi     L1302                    ; Branch if  temperature(ectFiltered) < 72degC                           

            ;------------------------------------------------------------------------------------------
            ; At this point engine is startingToCrank and temperature(iatChecked) >= 10degC 
            ; and temperature(ectFiltered) >= 72degC, set flag indicating vapor lock conditions exist, NOT???
            ;------------------------------------------------------------------------------------------
            orm     fpsBcsFlags, #$08        ; Set flag indicating vapor lock conditions exist

            ;--------------------------------------------------------------------
            ; Engine is running or notRotating or startingToCrank
            ; Check if we should reset vapor lock flag: 3 minutes after
            ; engine was started or if o2Fbk < $4d (meaning we are running rich)
            ;--------------------------------------------------------------------
L1302       ldaa    T0p5_crank1              ;                               
            adda    #$5a                     ;                         
            bcc     L1303                    ; branch to reset flag if engine stopped "startingToCrank" more than 180s ago (engine has been running for 3 minutes)
            ldaa    o2Fbk                    ; a = o2Fbk                         
            cmpa    #$4d                     ;                         
            bhi     L1304                    ; Dont reset if o2Fbk > $4d  (running lean???)                       
L1303       andm    fpsBcsFlags, #$f7        ; Reset vappor lock flag
                            
            ;---------------------------------------------
            ; Check whether we have vapor lock conditions
            ;---------------------------------------------
L1304       brset   fpsBcsFlags, #$08, L1305 ; Branch if vapor lock flag is set
                          
            ;---------------------------------------------------------------------
            ; Vapor lock flag is not set, at this point b = old fpsBcsFlags
            ; Check if solenoid deactivation is just happening now and 
            ; set flag to indicate so
            ;---------------------------------------------------------------------
            bitb    #$08                     ;                         
            beq     L1307                    ; Branch to reset solenoid if bit was also 0 on previous iteration                         
            orm     fpsBcsFlags, #$04        ; Set flag indicating solenoid was just deactivated                            
            bra     L1307                    ; Branch to deactivate it                         

            ;----------------------------------------------
            ; Vapor lock flag is set, check additional 
            ; conditions before activating solenoid 
            ;----------------------------------------------
L1305       ldaa    T40_crank                  ;                              
            adda    #$50                       ;                         
            bcs     L1306                      ; branch to activate solenoid if engine stopped "startingToCrank" less than 2s ago                              
            brset   closedLpFlags, #$01, L1307 ; Branch to deactivate solenoid if the ECU has determined that we should be using closed loop mode (or getting close to it)                          

            ;-------------------------------------
            ; Activate the fuel pressure solenoid
            ;-------------------------------------
L1306       andm    port5, #$ef             ; Activate the fuel pressure solenoid                                 
            bra     L1309                                                 

            ;----------------------------------------
            ; Deactivate the fuel pressure solenoid
            ;----------------------------------------
L1307       orm     port5, #$10             ; Deactivate the fuel pressure solenoid                                 
L1309       rts                                                          



;******************************************************************
;
;
; Second subroutine
;
;
;******************************************************************
            ;--------------------------------------------------
            ; Build port3Snap1 from port3Snap0 using a 
            ; 
            ; Set port3Snap1.2 if vssCnt1!=0, reset otherwise
            ;--------------------------------------------------
subroutine2 ldaa    port3Snap0              ; start with a = port3Snap1 = port3Snap0                                  
            anda    #$fb                    ; reset 00000100                             
            ldab    vssCnt1                 ; b = vssCnt1                                
            beq     L1311                   ;                               
            oraa    #$04                    ; Set flag

            ;---------------------------------------------------------------
            ; Reset iscFlags0.6 if key is in start and T40_noPower not expired?????? 
            ; (meaning engine is cranking and battery not KO? 
            ;---------------------------------------------------------------
L1311       bita    #$40                    ;                              
            bne     L1312                   ; Bail if key is not is start                              
            tst     T40_noPower             ; Key in start                               
            beq     L1312                   ; Bail if timer expired                              
            andm    iscFlags0, #$bf         ; Key in start and timer not expired, reset max calibration flag 0100 0000

            ;----------------------------------------------------------
            ; Re-init T40_noPower at 5 (0.125s) if ECU still has power
            ;----------------------------------------------------------
L1312       bita    #$02                    ;                              
            bne     L1313                   ; Branch if IG1 at 0V (No more power, ECU about to turn off?)                              
            ldab    #$05                    ; ECU not about to turn off, restart timer                             
            stab    T40_noPower             ;                              

            ;-------------------------------------------
            ; Move old port3Snap1 to oldP3Snap1 and 
            ; update port3Snap1 with new value
            ;-------------------------------------------
L1313       ldab    port3Snap1              ; b = old port3Snap1                              
            staa    port3Snap1              ; port3Snap1 = new port3Snap1                              
            stab    oldP3Snap1              ; oldP3Snap1 = old port3Snap1                               

            ;-------------------
            ; Update iscStepMax 
            ;-------------------
            ldaa    #$78                    ; I believe this is the max iscStepCurr value (120 decimal)                           
            staa    iscStepMax              ; iscStepMax = max possible value?                                
            nop                             ;                             
            nop                             ;                             
            nop                             ;
                                                                    
            ;---------------------------------------------------------------
            ; Decrement T40s_iscStable at 40Hz if iscStepCurr = iscStepTarg   
            ;---------------------------------------------------------------
            ldaa    iscStepTarg             ;                                 
            cmpa    iscStepCurr             ;                                
            bne     L1314                   ; Branch if iscStepCurr != iscStepTarg                             
            ldx     #T40s_iscStable         ;                                   
            jsr     decX40Hz                ; Decrement T40s_iscStable at 40Hz 

            ;-----------------------------------------------------
            ; If engine is notRotating, re-init some ISC variables
            ;-----------------------------------------------------
L1314       brclr   state1, #$10, L1315     ; Bail if notRotating clear
            jsr     iscYnInit               ; Init isc variables
            clr     iscStStall              ;                              
#ifdef E932
            clr     iscStBaseAcAdj          ;                              
#endif
            andm    iscFlags1, #$5f         ; reset flags used when engine rotating or running, 1010 0000                                
            orm     iscFlags1, #$01         ; set flag (flag is only 0 when key in start and iscStTargSpec = iscStepCurr)

            ;-----------------------------------------------------
            ; Update isc stable timer if  power 
            ; steering flag changed since last time
            ;-----------------------------------------------------
L1315       ldaa    port3Snap1               ;                                  
            eora    oldP3Snap1               ;                                  
            bita    #$08                     ;                            
            beq     L1316                    ; Branch if port3Snap1.3 did not change value since last time                             
            ldab    #$50                     ;                            
            jsr     updIscStableTimer        ;                                 

            ;-----------------------------------------------------
            ; Update isc stable timer if A/C state
            ; changed since last time 
            ;-----------------------------------------------------
L1316       bita    #$10                     ;                            
            beq     L1317                    ; Branch if port3Snap1.4 did not change value since last time                             
            ldab    #$50                     ;                            
            jsr     updIscStableTimer        ;                                 
L1317       .equ    $                        ;

            ;-----------------------------------------------------
            ; Update isc stable timer if park/neutral
            ; changed since last time (E932)
            ;-----------------------------------------------------
#ifdef E932                                  
            bita    #$20                     ;                            
            beq     L1319                    ; Branch if port3Snap1.5 did not change value since last time                             
            ldab    #$50                     ;                            
            brclr   port3Snap1, #$20, L1318  ; Makes no difference, $50 used anyway...
            ldab    #$50                     ;                            
L1318       jsr     updIscStableTimer        ;                                 
#endif

            ;-----------------------------------------------------
            ; Update isc stable timer if tpsDiffMax2 > $04
            ; i.e. gas pedal is moving...
            ;-----------------------------------------------------
L1319       ldaa    tpsDiffMax2              ;                                   
            cmpa    #$04                     ;                            
            bcs     L1320                    ;                             
            ldab    #$28                     ;                            
            jsr     updIscStableTimer        ;                                 

            ;----------------------------------------------------------------
            ; Update isc stable timer if idle switch is off
            ; Timer value is from table t_iscStableIdleSw
            ; Timer will only start counting when idle switch is back on...
            ;----------------------------------------------------------------
L1320       ldaa    port3Snap1              ;                                    
            bmi     L1323                   ; Bail if idle switch is ON                             
            ldd     rpm4                    ;                             
            lsrd                            ; d = rpm4/2                             
            subb    idleSpdTarg             ;                              
            sbca    #$00                    ; d = rpm4/2 - idleSpdTarg                            
            bcc     L1321                   ; Branch if no overflow                              
            clra                            ;                             
            clrb                            ; Use min of d=0                             
L1321       lsrd                            ;                             
            lsrd                            ; d = (rpm4/2 - idleSpdTarg)/4                              
            cmpd    #$00a0                  ;                               
            bcs     L1322                   ; Branch if (rpm4/2 - idleSpdTarg)/4 < $a0 (5000rpm)
            ldab    #$a0                    ; Use max of $a0 (5000rpm)                            
L1322       tba                             ; a = (rpm4/2 - idleSpdTarg)/4                             
            ldx     #t_iscStableIdleSw      ;                               
            jsr     interp16b               ; b = t_iscStableIdleSw((rpm4/2 - idleSpdTarg)/4)                                 
            jsr     updIscStableTimer       ;                                  

            ;---------------------------------------------------
            ; Update isc stable timer if engine is not runnning
            ; or if min or max isc calibration is ongoing or if  
            ; we have ignition problems
            ;---------------------------------------------------
L1323       brset   state1, #$11, L1324        ; Branch to update if notRotating or startingToCrank
            brset   iscFlags0, #$a0, L1324     ; Branch to update if min or max calibration requested flag is set
            brclr   coilChkFlags, #$80, L1325  ; Bail if no problem found on ignition signal
L1324       ldab    #$78                       ; 
            jsr     updIscStableTimer          ; 

            ;-----------------------------------------------------------------
            ; Update idleSpdInit = t_idleSpd(ect) or t_idleSpdDr(ect) (E932)
            ;-----------------------------------------------------------------
L1325       .equ    $
#ifdef E931
            ldx     #t_idleSpd               ;                                   
            jsr     interpEct                ; b = t_idleSpd(ect)                                  
#else
            ldx     #t_idleSpdDr             ;                                     
            brclr   port3Snap1, #$20, L1326  ;                                    
            ldx     #t_idleSpd               ;                                  
L1326       jsr     interpEct                ;                                 
#endif
            stab    idleSpdInit              ; idleSpdInit = t_idleSpd(ect) or t_idleSpdDr(ect)                                   

            ;-----------------------------------------------------------------
            ; Update idleSpdMin with 0 if A/C switch is on 
            ; or if AT is in drive or if T0p5_crCold timer expired 
            ;-----------------------------------------------------------------
            clrb                             ; preload default value of 0                            
            ldaa    port3Snap1               ;                                  
            anda    #$30                     ;                            
            cmpa    #$30                     ;                            
            bne     L1328                    ; Branch to use default of 0 if A/C switch is on or if AT is in drive
            ldaa    T0p5_crCold              ;                              
            beq     L1328                    ; Branch to use default of 0 if T0p5_crCold timer expired                            

            ;-----------------------------------------------
            ; A/C switch is off and AT is in not in drive 
            ; and  T0p5_crCold timer not expired
            ;
            ; Compute  idleSpdMin
            ;-----------------------------------------------
            ldaa    #$3c                     ; a = $3c                            
            staa    temp1                    ; temp1 = $3c                            
            ldaa    #$13                     ; a = $13                            
            brset   iscFlags1, #$20, L1327   ; Branch if engine startingToCrank and temperature(iat) < 75degC
#ifdef E931
            ldaa    #$20                     ; Use higher value                           
#else
            ldaa    #$13                     ; Use same value                            
#endif
L1327       ldab    T0p5_crCold              ; b = T0p5_crCold                              
            mul                              ; d = ($13 or $20) * T0p5_crCold                           
            div     temp1                    ; b = ($13 or $20) * T0p5_crCold / $3c                            
            addb    t_idleSpd                ; b = ($13 or $20) * T0p5_crCold / $3c + t_idleSpd(0)                                 
L1328       stab    idleSpdMin               ; idleSpdMin = 0 or (t_idleSpd(0) + (0.32 0r 0.53) * T0p5_crCold)                             

            ;----------------------------------------------------------------------------------
            ; Update idleSpdTarg from idleSpdInit and idleSpdMin and A/C park/neutral conditions
            ;----------------------------------------------------------------------------------
            ldaa    idleSpdInit             ; a = idleSpdInit                              
            brset   port3Snap1, #$10, L1331 ; Branch if A/C switch is off?                               
#ifdef E932
            ldab    #$53                    ; 648rpm                             
            brclr   port3Snap1, #$20, L1330 ; Branch if park/neutral???                                   
#endif
            ldab    #$6d                    ; 852rpm                            
L1330       cba                             ;                             
            bcc     L1331                   ; Branch if idleSpdInit >= $6d                              
            tba                             ; Use min of a = $6d 
                                         
L1331       cmpa    idleSpdMin              ;                              
            bcc     L1332                   ; Branch if idleSpdInit >= idleSpdMin                            
            ldaa    idleSpdMin              ; Use min of idleSpdMin                             
L1332       staa    idleSpdTarg             ; idleSpdTarg = ...                             


#ifdef E931
            ;-------------------------------------------
            ; Update iscStBase for E931
            ; iscStBase = t_iscStEct0(ect)
            ;-------------------------------------------
            ldx     #t_iscStEct0            ;                                     
            jsr     interpEct               ;                                   
            stab    iscStBase               ; iscStBase = t_iscStEct0(ect)                              
#else       
            ;------------------------------------------------------------------
            ; Update iscStBase for E932
            ; Choose a different table if transmission is engaged (e.g. drive)
            ;
            ; iscStBase = t_iscStEct1(ect) or t_iscStEct0(ect) 
            ;------------------------------------------------------------------
            ldx     #t_iscStEct1            ;                               
            brclr   port3Snap1, #$20, L1334 ; Branch if park/neutral                                    
            ldx     #t_iscStEct0            ;                                    
L1334       jsr     interpEct               ;                                  
            stab    iscStBase               ; iscStBase = t_iscStEct0(ect) or t_iscStEct1(ect)                               

            ;-------------------------------------------------------------------
            ; For E932, decrement iscStBaseAcAdj by 1 (min of 0) at ~2.2Hz 
            ;-------------------------------------------------------------------
            ldaa    T40_21                  ; a = T40_21                              
            bne     L1336                   ; Branch if timer not expired                             
            ldaa    #$12                    ; Timer expired, re-init to 0.45sec                            
            staa    T40_21                  ; T40_21 = 0.45sec                              
            ldaa    iscStBaseAcAdj          ; a = iscStBaseAcAdj                             
            suba    #$01                    ; a = iscStBaseAcAdj - 1                            
            bcc     L1335                   ; Branch if no underflow                              
            clra                            ; Underflow, use min of 0                            
L1335       staa    iscStBaseAcAdj          ; update iscStBaseAcAdj                             
#endif

            ;---------------------------------------------------
            ; Compute iscStBaseAc, basic iscStep corrected for 
            ; additional A/C and transmission load
            ;---------------------------------------------------
L1336       clra                            ; preload default value of offset = 0                             
            brset   port3Snap1, #$10, L1342 ; Bail to use offset of 0 if A/C switch off                                     
            ldaa    #$1c                    ; A/C is on, offset = a = $1c                            
            ldab    #$37                    ; minValue = b = $37                            
#ifdef E932
            brset   port3Snap1, #$20, L1337 ; Branch if park/neutral                                   
            ldaa    #$0a                    ; AT in drive, offset = $0a                           
            ldab    #$25                    ; minValue = $25                            
#endif
L1337       adda    iscStBase               ; a = t_iscStEct0(ect) + offset                              
            bcc     L1338                   ; Branch if no overflow                             
            ldaa    #$ff                    ; Use max of $ff                            
L1338       cba                             ;                             
            bcc     L1339                   ; Branch if t_iscStEct0(ect) + offset >= minValue                              
            tba                             ; Use minValue                             
L1339       .equ    $
#ifdef E932
            brclr   port3Snap1, #$20, L1341 ; Branch if AT not in park/neutral
            staa    iscStBaseAcAdj          ; AT in park, iscStBaseAcAdj = t_iscStEct0(ect) + offset                               
            bra     L1342                   ;                              
L1341       cmpa    iscStBaseAcAdj          ; AT in drive, update iscStBaseAc with minimum of iscStBaseAcAdj                             
            bcc     L1342                   ;                              
            ldaa    iscStBaseAcAdj          ;                              
#endif
L1342       staa    iscStBaseAc             ; For E931, iscStBaseAc = min(t_iscStEct0(ect) + offset, minValue)

                                              
            ;------------------------------------------------------------------
            ; Init iscStStartUsed and iscStStartMaster as long as we are 
            ; startingToCrank. These values are used at engine startup
            ;------------------------------------------------------------------
            brclr   state1, #$01, L1343     ; Bail if startingToCrank clear
            ldx     #L2023                  ; Engine is startingToCrank                               
            jsr     interpEct               ; b = L2023(ect)                                 
            stab    iscStStartUsed          ; iscStStartUsed = L2023(ect)                               
            stab    iscStStartMaster        ; iscStStartMaster = L2023(ect)                             

            ;----------------------------------------------------------------
            ; Section to update iscStStartUsed, iscStStartMaster
            ; and eventually iscYn after the engine is started
            ;
            ; learning variable iscYn is only updated after a certain delay 
            ; has passed since the engine was started. At that point we have 
            ; a good idea of how far we are from the ideal isc step we 
            ; should be using...
            ;----------------------------------------------------------------
            ;------------------------------------------
            ; First check if basic conditions are met 
            ;------------------------------------------
L1343       brset   state1, #$11, L1349     ; bail if notRotating or startingToCrank 
            ldaa    iscStStartMaster        ; a = iscStStartMaster 
            beq     L1349                   ; Bail if iscStStartMaster = 0 (we already updated iscYn once)                             
            ldaa    T40_iscStart            ;                                
            bne     L1347                   ; Branch if T40_iscStart no yet expired                               

            ;---------------------------------------------------------------
            ; Engine is running, iscStStartMaster!=0 and T40_iscStart is expired
            ;---------------------------------------------------------------
            ;--------------------------------------------------------------------------
            ; Decrement iscStStartMaster by 1 (min of 0) at around 6Hz (3Hz if cold)
            ;
            ; T40_iscStart is initialized with values from L2024(ect) on
            ; every timer expiry, if L2024(ect)=7 then freqency 
            ; will be around 6Hz... In colder temperature, iscStStartMaster will
            ; be decremented at a slower rate, e.g 3Hz
            ;--------------------------------------------------------------------------
            ldx     #L2024                  ; x points to L2024                              
            jsr     interpEct               ; b = L2024(ect)                                 
            stab    T40_iscStart            ; T40_iscStart = L2024(ect)                                
            dec     iscStStartMaster        ; iscStStartMaster = iscStStartMaster - 1                              
            bne     L1347                   ; Branch if iscStStartMaster!=0                             

            ;------------------------------------------------------------------------
            ; iscStStartMaster reached 0, update iscYn = old iscYn + iscStStartUsed + L2023(ect)
            ; and reset iscStStartUsed since we are now finished updating iscYn
            ; i.e. both iscStStartMaster and iscStStartUsed are now 0
            ;
            ; Basically, update the isc learning variables with how much isc offset
            ; was required to get the isc step stable upon engine startup. If isc
            ; was not stable then iscStStartUsed=0 and we didn't learn anything...
            ;------------------------------------------------------------------------
            jsr     iscPointers             ;                                 
            ldaa    iscStStartUsed          ; a = iscStStartUsed
            adda    $00,y                   ; a = iscStStartUsed + iscYn, y = y+1                              
            decy                            ; y = y - 1                            
            bcc     L1346                   ; Branch if no overflow                             
            ldaa    #$ff                    ; Use max of $ff                            
L1346       staa    $00,y                   ; iscYn = old iscYn + iscStStartUsed + L2023(ect)
            clr     iscStStartUsed          ; iscStStartUsed = 0 since we are now finished updating iscYn
                                         
            ;-------------------------------------------------
            ; Check if we should re-init isc Yn variables???
            ;-------------------------------------------------
L1347       ldaa    T40s_iscStable           ;                                  
            bne     L1348                    ; Branch to re-init if T40s_iscStable not expired, i.e. isc is not yet stable                            
            brset   iscLrnFlags, #$10, L1350 ; Branch if conditions are good to update isc learning variables

            ;-------------------------------------------------
            ; At this point, isc is not yet stable or 
            ; conditions are not good to update isc variables
            ;
            ; Re-init isc Yn variables 
            ;-------------------------------------------------
L1348       jsr     iscYnInit               ;                                     

            ;----------------------------------------------------------------------------
            ; At this point isc not yet stable or engine notRotating or startingToCrank
            ; iscStStartUsed = iscStStartMaster 
            ; 
            ; Basically synch the isc step currently in use with the master value
            ;----------------------------------------------------------------------------
L1349       ldaa    iscStStartMaster        ; a = iscStStartMaster                              
            staa    iscStStartUsed          ; iscStStartUsed = iscStStartMaster                             

            ;-----------------------------------------------------------------------
            ; Decrement iscStStall by 3 (min of 0) at 20Hz (T40_stall looping at 2?)???
            ;-----------------------------------------------------------------------
L1350       ldaa    iscStStall              ; a = iscStStall                             
            beq     L1355                   ; Bail if iscStStall already at 0                              
            ldab    T40_stall                  ;                               
            bne     L1352                   ; Branch if T40_stall not expired                              
            suba    #$03                    ; a = iscStStall-3                            
            bcc     L1351                   ; Branch if no underflow                            
            clra                            ; use min of 0                           
L1351       staa    iscStStall              ; iscStStall = max(iscStStall-3, 0)                            
L1352       ldab    #$02                    ; b = $02                           
#ifdef E932
            brset   port3Snap1, #$20, L1353 ; Branch if park/neutral                                    
            ldab    #$02                    ; Use same value anyway...                             
#endif
L1353       ldaa    T40_stall                  ; a = T40_stall                              
            beq     L1354                   ; Branch if T40_stall expired                             
            cba                             ;                              
            bcc     L1354                   ; Branch to use 2 if T40_stall >= 2                              
            tab                             ; Use b = T40_stall when T40_stall < 2                           
L1354       stab    T40_stall                  ; T40_stall = min(T40_stall, 2)                              

            ;--------------------------------------------
            ; Re-init T40_revving to 0.5sec if  
            ; tpsRaw < 86% or airVol >= $3a  ???
            ;
            ; T40_revving will start counting when tpsRaw>86%
            ; and airVol < $3a???? 
            ;--------------------------------------------
L1355       ldaa    tpsRaw                  ; a = tpsRaw                              
            cmpa    #$dc                    ;                             
            bcs     L1356                   ; Branch to re-init if tpsRaw < 86%                             
            ldaa    airVol                  ; a = airVol                              
            cmpa    #$3a                    ;                             
            bcs     L1357                   ; Branch if airVol < $3a                             
L1356       ldaa    #$14                    ; 0.5sec                            
            staa    T40_revving             ; Re-init T40_revving to 0.5sec                              

            ;-------------------------------------------------
            ; Set iscFlags1.7 flag if T40_revving is expired
            ;
            ; Basically, this flag is set when tps has been 
            ; high and airVol low for more than 0.5sec 
            ;-------------------------------------------------
L1357       andm    iscFlags1, #$7f         ; Assume flag is 0                               
            ldaa    T40_revving             ;                               
            bne     L1358                   ; Branch if T40_revving not expired                               
            orm     iscFlags1, #$80         ; T40_revving expired, set flag                                

            ;---------------------------------------------------------
            ; Section to update iscStStall as long as idle switch 
            ; is off and rpm8>=500 and iscFlags1.7 = 0 (set to 1 when 
            ; tps has been high and airVol low for more than 0.5sec)
            ;
            ; iscStStall will therefore be "stuck" to the value
            ; calculated when all these conditions were met the last 
            ; time. Basically says where we are coming from when 
            ; the throttle plate closes (likeliness of stalling the 
            ; engine...)??
            ;---------------------------------------------------------
            ;------------------------------
            ; First check those conditions
            ;------------------------------
L1358       ldaa    port3Snap1              ;                                   
            bmi     L1362                   ; Bail if idle position switch is on                             
            ldaa    iscFlags1               ;                              
            bmi     L1362                   ; Bail if  tps has been high and airVol low for more than 0.5sec
            ldaa    rpm8                    ;                             
            cmpa    #$40                    ; 500rpm                             
            bcs     L1362                   ; Bail if rpm8 < 500                             

            ;------------------------------------------------
            ; Set flag, not directly related to calculation
            ;------------------------------------------------
            orm     iscLrnFlags, #$20       ; 

            ;---------------------------------------------------------------
            ; Compute conditionned tps and store in temp2 for 
            ; table interpolation below
            ; condTps (with range of $00 to $a0) = 
            ;       2* max(min(tpsRaw,$ba)-$1a,0)      if tpsRaw <= 23%
            ;       max(min(tpsRaw,$ba)-$1a,0) + $20   if tpsRaw >  23%
            ;---------------------------------------------------------------
            ldab    tpsRaw                  ;                               
            ldx     #$ba1a                  ;                               
            jsr     clipOffset              ; b = max(min(tpsRaw,$ba)-$1a,0)-> returns b = $00 to $a0  (tpsRaw 10% to 73%)                                    
            cmpb    #$20                    ;                              
            bhi     L1359                   ; Branch if max(min(tpsRaw,$ba)-$1a,0) > $20 (tpsRaw>23%)                               
            aslb                            ; b =  2* max(min(tpsRaw,$ba)-$1a,0)                              
            bra     L1360                   ;                              
L1359       addb    #$20                    ; b = max(min(tpsRaw,$ba)-$1a,0) + $20                             
L1360       stab    temp2                   ; temp2 = condTps                             

            ;--------------------------------------------------------------
            ; Update iscStStall =  max(old iscStStall, t_iscStStall(condTps)) 
            ;--------------------------------------------------------------
            ldx     #t_iscStStall           ; x points to t_iscStStall                               
#ifdef E932
            brset   port3Snap1, #$20, L1361 ; Branch if park/neutral                                    
            ldx     #L2030                  ; x points to L2030 for E932                               
#endif
L1361       ldaa    temp2                   ; a = condTps                             
            jsr     interp32                ; b = t_iscStStall(condTps)                                 
            cmpb    iscStStall              ;                              
            bcs     L1362                   ; Branch if t_iscStStall(condTps) < iscStStall                             
            stab    iscStStall              ; iscStStall =  max(old iscStStall, t_iscStStall(condTps))
                                          
            ;--------------------------------------------------------
            ; If idle switch if off, 
            ; subtract (iscStepTarg - iscStepCurr) from iscStStall 
            ;
            ; Basically reduce iscStStall if the current isc step is
            ; lower than the target. Reduce it by the same amount...
            ;--------------------------------------------------------
L1362       ldaa    port3Snap1              ; a = port3Snap1                                  
            bpl     L1365                   ; Bail if idle switch is on                              
            eora    oldP3Snap1              ;                                   
            bpl     L1365                   ; Bail if it changed in that split second?????? (Am I missing something??? maybe they changed their mind...)                              

            ldab    iscStepTarg             ; b = iscStepTarg                                 
            subb    iscStepCurr             ; b = iscStepTarg - iscStepCurr                                
            bcc     L1363                   ; Branch if result positive                             
            clrb                            ; Use min of 0                            
L1363       ldaa    iscStStall              ; a = iscStStall                              
            sba                             ; a = iscStStall - (iscStepTarg - iscStepCurr)                            
            bcc     L1364                   ; Branch if no underflow                             
            clra                            ; Use min of 0                            
L1364       staa    iscStStall              ; iscStStall =  iscStStall - (iscStepTarg - iscStepCurr) 
                                                
            ;----------------------------------
            ; Update  iscStBarOff
            ;----------------------------------
L1365       ldaa    baroCond                ; a = baroCond                                  
            ldx     #t_iscStBaro            ;                                     
            jsr     interp32                ; b = t_iscStBaro(baroCond)                                
            stab    iscStBarOff             ; iscStBarOff = t_iscStBaro(baroCond)
                                                           
            ;--------------------------------------------
            ; Reset T0p5_crCold to 0 if notRotating
            ; or if T0p5_crCold >= $3c (not possible???)
            ;--------------------------------------------
            brset   state1, #$10, L1367     ; Branch to reset T0p5_crCold if notRotating
            ldaa    #$3c                    ;                             
            cmpa    T0p5_crCold             ;                                    
            bcc     L1368                   ; Branch if T0p5_crCold <= $3c                              
L1367       clr     T0p5_crCold             ; reset T0p5_crCold to 0                              

            ;---------------------------------------
            ; Update T0p5_crCold to $00 or $3c 
            ; and iscFlags1.1 flag when startingToCrank
            ;---------------------------------------
L1368       brclr   state1, #$01, L1370     ; Bail if startingToCrank clear
            clrb                            ; preload b=0                            
            ldaa    ectFiltered             ;                                    
            cmpa    #$1b                    ; 88degC                               
            bcc     L1369                   ; Branch if temperature(ectFiltered) <= 88degC                              
            ldab    #$3c                    ; b= $3c                             
L1369       stab    T0p5_crCold             ; T0p5_crCold = 0 or $3c                                
            andm    iscFlags1, #$df         ; Assume we reset bit                                
            ldaa    iatChecked              ;                                   
            cmpa    #$29                    ; 75degC                             
            bcs     L1370                   ; Branch if temperature(iat) > 75degC
            orm     iscFlags1, #$20         ; Set flag                                

            ;-------------------------------------------------------------
            ; Update iscStBaseCSt if T0p5_crCold not expired, else use iscStBaseCSt = 0
            ;
            ;      iscStBaseCSt =  (0 or $1e or $0f) * T0p5_crCold / $3c +  t_iscStEct0
            ;
            ; iscStBaseCSt is basically the iscStep when a cold engine 
            ; is being started, starts with a high value and then is 
            ; decreased (through T0p5_crCold) towards normal  isc step 
            ; over a period of 120sec
            ;-------------------------------------------------------------
L1370       clrb                            ; preload b = 0                            
            ldaa    T0p5_crCold             ;                                    
            beq     L1372                   ; Bail to store 0 if T0p5_crCold expired                              
            ldaa    #$3c                    ;                             
            staa    temp1                   ; temp1 = $3c                               
#ifdef E931
            ldaa    #$1e                    ; assume low iat, high value...a = $1e                            
#else
            ldaa    #$19                    ;                             
#endif
            brclr   iscFlags1, #$20, L1371  ; Branch if not (startingToCrank and temperature(iat) < 75degC)                               
            ldaa    #$0f                    ; high iat, use lower value... a = $0f                            
L1371       ldab    T0p5_crCold             ; b = T0p5_crCold                                   
            mul                             ; d = $1e * T0p5_crCold                            
            div     temp1                   ; d = $1e * T0p5_crCold / $3c                            
            addb    t_iscStEct0             ; b = $1e * T0p5_crCold / $3c +  t_iscStEct0                                  
L1372       stab    iscStBaseCSt            ; iscStBaseCSt =  0 or $1e * T0p5_crCold / $3c +  t_iscStEct0                               

            ;--------------------------------------------------
            ; Check if iscStepCurr and iscStepCom are in synch?
            ;--------------------------------------------------
            sei                             ; We don't want ISC values to change during check                                           
            ldaa    iscStepCurr             ;                                                                                              
            coma                            ;                                                                                           
            anda    #$7f                    ;                                                                                           
            cmpa    iscStepCom              ;                                                                                                 
            cli                             ;                                                                                           
            bne     L1373                   ; Branch if  iscStepCurr and iscStepCom are not in synch                                             

            ;-------------------------------------------
            ; iscStepCurr and iscStepCom are in synch
            ; Check ISC variables against min/max
            ;-------------------------------------------
            ldx     #$b000                  ; x = $b000                                
            cpx     isc0                    ;                             
            bcs     L1373                   ; Branch to re-init if isc0 > $b000                               
            cpx     isc1                    ;                             
            bcs     L1373                   ; Branch to re-init if isc1 > $b000                              
            ldx     #$6c00                  ; x = $6c00                              
            cpx     isc0                    ;                             
            bhi     L1373                   ; Branch to re-init if isc0 < $6c00                             
            cpx     isc1                    ;                             
            bhi     L1373                   ; Branch to re-init if isc1 < $6c00                             
            brset   iscFlags0, #$20, L1374  ; Branch if the ISC needs min calibration
            bra     L1379                   ; Branch to continue processing normal flow???                              

            ;-----------------------------------------------
            ; iscStepCurr and iscStepCom are not in synch
            ; re-initialize ISC variables 
            ; set isc flag indicating we need min calibration
            ; reset all other isc flags
            ;-----------------------------------------------
L1373       ldd     #$8c00                  ;                               
            std     isc0                    ;                             
            std     isc1                    ;                             
            jsr     iscYnInit               ;                                     
            ldaa    #$20                    ; Set flag indicating we need to calibrate ISC, reset all other flags
            staa    iscFlags0               ;                              

            ;------------------------------------------------------------------------
            ; Section for ISC min calibration, code is triggered by iscFlags0.5 being set
            ;
            ; Min calibration proceed as follows. 
            ;
            ;       1) iscFlags0.5 is set to indicate calibration is required, 
            ;          iscStepCurr init to 135, iscStepTarg init to 0
            ;       2) iscFlags0.0 is set to indicate calibration is started, 
            ;          waiting for iscStepCurr to reach iscStepTarg of 0
            ;       3) iscFlags0.1 is set to indicate calibration is finished,
            ;          iscStepCurr reached 0, we are therefore now certain that
            ;          the isc pintle is physically at position 0.iscStepTarg 
            ;          is now init to 6, waiting for iscStepCurr to reach iscStepTarg
            ;       4) iscStepCurr reached iscStepTarg = 6, iscFlags0.0.1.5 
            ;          are all reset
            ; 
            ;------------------------------------------------------------------------
L1374       brset   iscFlags0, #$02, L1376  ; Branch if calibration is finished, we are waiting for ISC to go back to iscStepCurr=6                                
            brset   iscFlags0, #$01, L1375  ; Branch if calibration is started, we are waiting for ISC to reach iscStepCurr=0                              
            ldaa    #$87                    ; calibration not started, use iscStepCurr = a = $87  (135, above max, maybe during calibration?)                          
            sei                             ;                             
            jsr     iscStepComp             ; iscStepCurr = $87, iscStepCom = (~$87 & 7F) 
            cli                             ;                             
            orm     iscFlags0, #$01         ; Set flag indicating we just calculated iscStepCom?                              
L1375       clrb                            ; use iscStepTarg = b = 0                             
            ldaa    iscStepCurr             ; a = iscStepCurr                               
            bne     L1377                   ; Branch if iscStepCurr != 0                             
            orm     iscFlags0, #$02         ; iscStepCurr=0, set flag                               
L1376       ldab    #$06                    ; b = $06                            
            cmpb    iscStepCurr             ;                                
            beq     L1378                   ; Branch if iscStepCurr=$06                             
L1377       stab    iscStepTarg             ; iscStepTarg = $00 or $06                                
            jmp     L1389                   ; Bail
L1378       clra                            ; a = 0                            
            sei                             ;                             
            jsr     iscStepComp             ; iscStepCurr = $0, iscStepCom = (~$0 & 7F)                                   
            cli                             ;                             
            andm    iscFlags0, #$dc         ; Calibration is over, reset all flags 0010 0011                                

            ;--------------------------------------------------------
            ; Normal flow continues,
            ; Check if  max calibration need to be performed
            ;--------------------------------------------------------
L1379       brset   iscFlags0, #$80, L1380  ; Branch if max calibration is required?
            tst     T40_noPower             ;                                    
            bne     L1382                   ; Branch to normal flow if we are not about to loose power                              
            brset   iscFlags0, #$40, L1382  ; Branch to normal flow if max calibration already performed                              

            ;-------------------------------------------------------------
            ; At this point max calibration flag is set or we are about 
            ; to loose power and max calibration was not performed
            ;
            ; Set iscStepTarg to 135 if iscStepCurr not already at 135
            ;-------------------------------------------------------------
L1380       orm     iscFlags0, #$80         ; Set max calibration flag is case it was not set                               
            ldaa    #$87                    ; a = 135                            
            cmpa    iscStepCurr             ;                                
            beq     L1381                   ; Branch if iscStepCurr already at 135
            staa    iscStepTarg             ; Set target to iscStepTarg = 135                                
            jmp     L1389                   ;                              

            ;-------------------------------------------------------------
            ; At this point iscStepCurr is 135, we are therefore sure the 
            ; isc pintle is physically at its maximum value of 120,
            ; set iscStepCurr=120 and set/reset flags
            ;-------------------------------------------------------------
L1381       ldaa    #$78                    ; a = $78 (120, max usable value)                            
            sei                             ;                             
            jsr     iscStepComp             ; iscStepCurr = $78, iscStepCom = (~$78 & 7F)
            cli                             ;                             
            orm     iscFlags0, #$40         ; set flag 0100 0000, calibration done?                               
            andm    iscFlags0, #$7f         ; reset flag indicating we need max calibration 1000 0000                               

            ;-----------------------------------------------------
            ; if the ECU is about to loose power then 
            ;
            ; set/reset flags 
            ; use a fixed ISC step of $5a 
            ; don't re-init updIscStableTimer since we loose power...
            ;-----------------------------------------------------
L1382       andm    iscFlags0, #$ef         ; Assume we reset 0001 0000, updated below                               
            ldaa    T40_noPower             ;                                    
            bne     L1383                   ; Branch if timer not expired                             
            andm    iscFlags0, #$40         ; reset max calibration flag? 0100 0000                               
            orm     iscFlags0, #$10         ; Set 0001 0000                               
            ldab    #$5a                    ; b = $5a                            
            bra     L1388                   ; Branch to use fix ISC step of $5a, i.e. 3/4 of full range

            ;----------------------------------------------------
            ; If the engine is running but we are not receiving 
            ; airflow sensor interrupts then 
            ;
            ; set/reset flags
            ; re-init iscYn variables
            ; re-init updIscStableTimer
            ; use a fixed ISC step of $3a
            ;----------------------------------------------------
L1383       andm    iscFlags0, #$f7         ; Assume we reset 00001000, updated below                               
            brclr   state1, #$02, L1384     ; Bail if pulse accumulator interrupts are being received 
            brset   state1, #$11, L1384     ; Bail if notRotating or startingToCrank
            jsr     iscYnInit               ; Init variables                                     
            andm    iscFlags0, #$40         ; reset max calibration flag? 0100 0000                               
            orm     iscFlags0, #$08         ; set 0000 1000                               
            ldab    #$50                    ;                             
            jsr     updIscStableTimer       ; re-init updIscStableTimer                                 
            ldab    #$3a                    ; b = $3a                            
            bra     L1388                   ; Branch to use fix ISC step of $3a               
                           
            ;---------------------------------------------------
            ; Section to check for idle speed adjustment mode, 
            ; i.e. both ECU test mode terminal grounded and 
            ; timing adjustment terminal grounded                             
            ;---------------------------------------------------
L1384       andm    iscFlags0, #$fb         ; Reset 00000010
            ldaa    port4Snap               ; a = port4Snap                                  
            anda    #$18                    ; Keep only ECU test mode terminal grounded & timing adjustment terminal grounded               
            cmpa    #$18                    ; ECU test mode terminal grounded & timing adjustment terminal grounded                             
            bne     L1385                   ; Bail if not both of them grounded                             
            brset   port3Snap1, #$04, L1385 ; Both terminal grounded, bail if car is moving
#ifdef E932
            brclr   port3Snap1, #$20, L1385 ; Bail if not in park/neutral???                                    
#endif
            brclr   state1, #$11, L1386     ; branch if notRotating and startingToCrank clear

            ;------------------------------------------------------------
            ; Engine is either notRotating or startingToCrank
            ; Reset timer (always done when both terminal not grounded)
            ;------------------------------------------------------------
L1385       ldaa    #$08                    ; 0.2s 
            staa    T40_iSpAdj              ;                               

            ;--------------------------------------------------
            ; If Timer T40_iSpAdj is expired (0.2 sec after
            ; both terminals grounded) we are in basic idle 
            ; speed adjustment mode. Branch accordingly...
            ;--------------------------------------------------
L1386       ldaa    T40_iSpAdj              ;                               
            bne     L1390                   ; Branch to next section if timer not expired

            ;----------------------------------------------------
            ; Timer is expired, we are in basic idle 
            ; speed adjustment mode...
            ;
            ; Just compute iscStepTarg (target idle speed) as a
            ; function of temperature and barometric pressure,
            ; reset iscLrnFlags and iscStStall and exit from subroutine
            ;----------------------------------------------------
            orm     iscFlags0, #$04         ; Set flag                               
            ldab    #$50                    ;                             
            jsr     updIscStableTimer       ;                              
            ldx     #t_iscStEct0            ; x points to iscStepCurr(as a function of ECT) table                                
            jsr     interpEct               ; b = t_iscStEct0(ect), basic isc value we want as a function of ECT                                 
            addb    iscStBarOff             ; b = t_iscStEct0(ect) + iscStBarOff, Add an offset to compensate for barometric pressure
            bcc     L1388                   ; Branch if no overflow                             
            ldab    #$ff                    ; Use max
L1388       jsr     iscStepMaxFunc          ; Apply maximum to calculated value                            
            stab    iscStepTarg             ; iscStepTarg =  t_iscStEct0(ect) + iscStBarOff 
L1389       clra                            ;                             
            staa    iscLrnFlags             ; iscLrnFlags = 0                             
            staa    iscStStall              ; iscStStall = 0                             
            jmp     L1431                   ; Bail of subroutine
                                                           
            ;------------------------------------------------
            ; Basic idle speed adjustment mode is not active
            ; Section to update ISC stuff, long...
            ;------------------------------------------------
L1390       brset   state1, #$11, L1391     ; Branch if notRotating or startingToCrank

            ;--------------------------------------
            ; Engine is running, set /reset flags
            ;--------------------------------------
            andm    iscLrnFlags, #$fe       ; Reset bit 0                               
            orm     iscFlags1, #$01         ; Set flag indicating "normal running mode"??                               
            bra     L1392                   ; Branch to continue                             

            ;----------------------------------
            ; notRotating or startingToCrank
            ;----------------------------------
L1391       ldab    #$01                    ;                             
            stab    iscLrnFlags             ; Reset all bit to 0 and set bit 0 to 1                              

            ;---------------------------------------------------------------
            ; Reset iscFlags1.0 if key in start and iscStTargSpec = iscStepCurr??
            ;---------------------------------------------------------------
            brset   port3Snap1, #$40, L1392 ; Branch if key is not is start                                   
            ldaa    iscStTargSpec           ;                              
            cmpa    iscStepCurr             ;                                
            bne     L1392                   ; Branch if iscStTargSpec != iscStepCurr                             
            andm    iscFlags1, #$fe         ;                                

            ;------------------------------------------------------------------
            ; Init T40_acOnTrans to 0.1sec if A/C switch was just turned on?
            ;------------------------------------------------------------------
L1392       ldaa    port3Snap1              ;                                   
            eora    oldP3Snap1              ;                                   
            bita    #$10                    ;                             
            beq     L1393                   ; Branch if A/C switch did not change state                              
            brclr   port3Snap1, #$10, L1394 ; Branch if A/C switch is on                                   
L1393       .equ    $
#ifdef E931
            bra     L1395                   ;                               
#else
            bita    #$20                    ;                             
            beq     L1395                   ;                              
            brset   port3Snap1, #$20, L1395 ;                                    
#endif
L1394       ldab    #$04                    ; 0.1sec                            
            stab    T40_acOnTrans           ; T40_acOnTrans = 0.1sec
                                           
            ;--------------------------------------------------------------
            ; Update iscLrnFlags.2, flag indicating engine is running too slow? 
            ;--------------------------------------------------------------
L1395       ldaa    iscLrnFlags              ; a = old iscLrnFlags                             
            andm    iscLrnFlags, #$fb        ; Assume we reset 00000100, updated below                               
            ldab    ectFiltered              ;                                    
            cmpb    #$3c                     ; 55degC                             
            bcc     L1396                    ; Bail if temperature(ectFiltered) <= 55degC                               
            ldab    rpm8                     ;                             
            cmpb    #$40                     ;                             
            bcc     L1396                    ; Bail if rpm8 >=500                              
            brset   iscLrnFlags, #$01, L1396 ; Bail if engine is notRotating or startingToCrank (and basic idle speed adjustment mode is off)                              
            tst     T40_acOnTrans            ;                               
            bne     L1396                    ; Bail if timer not expired                              

            ;----------------------------------------------------------------------------------
            ; At this point 
            ;    temperature(ectFiltered) > 55degC 
            ;    rpm8 < 500rpm 
            ;    engine is running
            ;    T40_acOnTrans is expired (A/C switch was turned on more than 0.1sec ago, or never...)
            ;
            ; Set iscLrnFlags.2 indicating the engine is running to slow 
            ; (even though A/C transcient was ignored for 0.1sec)
            ;
            ; Clear T40_checkTargRpm if this condition was just detected in order to perform
            ; current versus target rpm comparison right away and adjust isc step before 
            ; the engine stalls...
            ;----------------------------------------------------------------------------------
            orm     iscLrnFlags, #$04       ; set 0000 0100                               
            anda    #$04                    ; a = old iscLrnFlags & 0000 0100                            
            bne     L1396                   ; Bail if old iscLrnFlags.2 was set                              
            clr     T40_checkTargRpm        ; old iscLrnFlags.2 was not set, reset timer to trigger fast rpm update... 
                                           
            ;---------------------------------
            ; Update updIscStableTimer if ???  
            ;---------------------------------
L1396       brclr   iscLrnFlags, #$20, Ne301 ; Branch if                                
            ldab    #$50                     ;                             
            jsr     updIscStableTimer        ;                                         
Ne301        .equ    $

            ;--------------------------------------------
            ; Update updIscStableTimer if ???  for E931 
            ;--------------------------------------------
#ifdef E931
            brclr    ftrimFlags, #$08, L1397 ; Branch if not (speed>24km/h and port3.0 is set???)                                      
            ldab    #$50                     ; speed>24km/h and port3.0 is set, update timer                            
            jsr     updIscStableTimer        ;                                          
#endif

            ;-------------------------------------------------------------------
            ; Section to update iscLrnFlags.4, flag indicating that conditions are
            ; good to update the isc learning variables???
            ;-------------------------------------------------------------------
L1397       andm    iscLrnFlags, #$ef       ; Assume we reset iscLrnFlags.4 (0001 0000)                                
            ldaa    port3Snap1              ;                                   
            bpl     L1398                   ; Branch if idle position switch is off                              
            brset   port3Snap1, #$04, L1398 ; Branch if car is moving
            ldaa    T40s_iscStable          ;                                  
            bne     L1398                   ; Branch if isc not stable yet
            ldaa    rpm8                    ;                             
            cmpa    #$2a                    ;                             
            bcc     L1399                   ; Branch if rpm8 >= 328rpm                              
L1398       brclr   state1, #$01, L1400     ; Branch if startingToCrank clear
            brset   iscFlags1, #$01, L1400  ; Branch if not (key in start and iscStTargSpec = iscStepCurr)

            ;--------------------------------------------
            ; At this point
            ;      car is not moving
            ; and idle switch is on 
            ; and isc is stable
            ; and rpm8 >= 328
            ;
            ; or these conditions are not met but 
            ;     engine is startingToCrank 
            ; and (key in start and iscStTargSpec = iscStepCurr)
            ;
            ; Set iscLrnFlags.4 indicating we can update the isc 
            ; learning variables?
            ;--------------------------------------------
L1399       orm     iscLrnFlags, #$10       ;                                
            bra     L1401                   ;                              

            ;-----------------------------------------------------
            ; At this point, 
            ;     car is moving
            ;  or idle position switch is off 
            ;  or isc not yet stable
            ;  or rpm < 328
            ;
            ; and engine is startingToCrank or key is not 
            ; in start or iscStTargSpec != iscStepCurr
            ;
            ; Re-init T40_iscLrn to 5sec
            ; Conditions are not good to update ISC learning variables?
            ; Flag is already reset so just reset that timer so that
            ; we have a 5sec delay when we can go back to being able
            ; to update them...
            ;--------------------------------------------------------------
L1400       ldab    #$c8                    ; 5sec                            
            stab    T40_iscLrn              ; T40_iscLrn = 5sec                               

            ;---------------------------------------------------------------------------------------------------
            ; Check whether abs(idleSpdTarg - rpm8) > (5/256 * idleSpdTarg)
            ;
            ; Basically chech if target and current rpm are more than 2% apart                            
            ;---------------------------------------------------------------------------------------------------
L1401       brclr   iscLrnFlags, #$10, L1403 ; Bail if conditions are not good to update isc variables                               
            ldaa    T40_checkTargRpm         ;                               
            bne     L1403                    ; Bail if timer not expired                             
            ldaa    idleSpdTarg              ; a = idleSpdTarg                                  
            suba    rpm8                     ; a = idleSpdTarg - rpm8                            
            ror     temp2                    ; shift sign (carry) of result in temp2.7
            bpl     L1402                    ; Branch if (idleSpdTarg - rpm8) >= 0                             
            nega                             ; a =  abs(idleSpdTarg - rpm8)                            
L1402       psha                             ; st0 = abs(idleSpdTarg - rpm8)                            
            ldaa    idleSpdTarg              ; a = idleSpdTarg                                   
            ldab    #$0a                     ; b = $0a                             
            mul                              ; d = $0a * idleSpdTarg                            
            pulb                             ; b = abs(idleSpdTarg - rpm8); a = $0a/256 * idleSpdTarg                            
            cba                              ;                             
            bcs     L1404                    ; Branch if ($0a/256 * idleSpdTarg) < abs(idleSpdTarg - rpm8), basically branch if difference between current rpm and desired one is too high                            
L1403       jmp     L1416                    ; Jump to next section
                             
            ;------------------------------------------------------------------
            ; At this point abs(idleSpdTarg - rpm8) > (5/256 * idleSpdTarg)
            ; or equivalently  abs(idleSpdTarg - rpm8)/idleSpdTarg > 2%
            ; i.e. Target and current rpm are more than 2% apart
            ;
            ; Section to update iscYn (until L1415).
            ;
            ; Basically this section increases the current iscYn (iscY1, iscY2 
            ; or iscY3) if the current rpm is lower than the target and vice-versa
            ; iscYn is centered at $80 (100%, no correction). The isc step used 
            ; is increase/decreased by iscYn-$80 later in the code
            ;------------------------------------------------------------------
L1404       aslb                            ; b = 2 * abs(idleSpdTarg - rpm8)                            
            bcs     L1405                   ; branch to use max of $ff if overflow                             
            aslb                            ; b = 4 * abs(idleSpdTarg - rpm8)                             
            bcc     L1406                   ; Branch if no overflow                             
L1405       ldab    #$ff                    ; use max of $ff                            
L1406       stab    temp1                   ; temp1 = 4 * abs(idleSpdTarg - rpm8)                              
            ldx     #L2035                  ; x point to L2035                               
            ldaa    temp1                   ; a = 4 * abs(idleSpdTarg - rpm8)                              
            jsr     interp32                ; b = L2035(4 * abs(idleSpdTarg - rpm8))                                
            stab    temp1                   ; temp1 = L2035(4 * abs(idleSpdTarg - rpm8))                              
            jsr     iscPointers             ; have x point to isc0 or isc1 and have y point to iscY0, iscY1 or iscY2                                
            ldab    $00,y                   ; b = iscYn, y = y + 1                              
            decy                            ; y = y-1, points back to same value                             
            ldaa    temp2                   ; a.7 = sign(carry) of idleSpdTarg - rpm8 (see above L1402)
            bpl     L1410                   ; Branch if  idleSpdTarg - rpm8 was positive

            ;---------------------------------------------------------------------------
            ; idleSpdTarg - rpm8 was negative. i.e. current rpm is too high
            ; Compute b = iscYn - min (iscStepTarg, L2035(4 * abs(idleSpdTarg - rpm8)))                             
            ;---------------------------------------------------------------------------
            ldaa    iscStepTarg             ; a = iscStepTarg                                   
            beq     L1416                   ; Branch if iscStepTarg = 0                             
            cmpa    temp1                   ;                              
            bhi     L1408                   ; Branch if iscStepTarg > L2035(4 * abs(idleSpdTarg - rpm8))
            staa    temp1                   ; Use max of = iscStepTarg                             
L1408       subb    temp1                   ; b = iscYn - min (iscStepTarg, L2035(4 * abs(idleSpdTarg - rpm8)))                             
            bcc     L1409                   ; Branch if no underflow                             
            clrb                            ; Use min of 0                            
L1409       bra     L1412                   ; 
                             
            ;-------------------------------------------------------------------------------------
            ; idleSpdTarg - rpm8 was positive, i.e. current rpm is too low
            ; Compute b = iscYn + min(iscStepMax - iscStepTarg, L2035(4 * abs(idleSpdTarg - rpm8)) 
            ;-------------------------------------------------------------------------------------
L1410       ldaa    iscStepMax              ; a = iscStepMax                                   
            suba    iscStepTarg             ; a = iscStepMax - iscStepTarg                                  
            beq     L1416                   ; Branch if iscStepTarg = iscStepMax
            cmpa    temp1                   ;                              
            bhi     L1411                   ; Branch if iscStepMax - iscStepTarg > L2035(4 * abs(idleSpdTarg - rpm8))                               
            staa    temp1                   ; Use max of iscStepMax - iscStepTarg                             
L1411       addb    temp1                   ; b = iscYn + min(iscStepMax - iscStepTarg, L2035(4 * abs(idleSpdTarg - rpm8)) 
            bcc     L1412                   ; Branch if no overflow                              
            ldab    #$ff                    ; Use max of $ff                            

            ;-------------------------------------------------------------------------------------
            ; at this point 
            ;        b = iscYn - min(iscStepTarg, L2035(4 * abs(idleSpdTarg - rpm8)))                             
            ;     or
            ;        b = iscYn + min(iscStepMax - iscStepTarg, L2035(4 * abs(idleSpdTarg - rpm8)) 
            ;
            ; Restart T40_checkTargRpm to 1 sec and decide whether to apply min/max to new iscYn=b value
            ;-------------------------------------------------------------------------------------
L1412       ldaa    #$28                     ; 1sec                            
            staa    T40_checkTargRpm         ; T40_checkTargRpm = 1sec                              
            brset   iscLrnFlags, #$01, L1413 ; Branch to min/max checking if engine is notRotating or startingToCrank                              
            bra     L1415                    ; Branch to store b in iscYn, Skip min/max checking                             
            nop                              ;                             

            ;-------------------------------------------------
            ; Check b for min and max and then store in iscYn
            ;-------------------------------------------------
L1413       cmpb    #$86                    ;                             
            bcs     L1414                   ; Branch if b < $86                             
            ldab    #$86                    ; Use max of $86                            
L1414       cmpb    #$7b                    ;                             
            bcc     L1415                   ; Branch if b >= $7b                             
            ldab    #$7b                    ; Use min of $7b                            
L1415       stab    $00,y                   ; iscYn = b....                             


            ;---------------------------------------------------------------
            ; re-init iscYn variables if car is moving and rpm8>=1000rpm
            ;---------------------------------------------------------------
L1416       brclr   port3Snap1, #$04, L1417 ; Branch if car is not moving                                    
            ldaa    rpm8                    ;                             
            cmpa    #$80                    ;                             
            bcs     L1417                   ; Branch if rpm8 < 1000rpm                              
            jsr     iscYnInit               ;
                                                 
            ;--------------------------------------------------------
            ; Transfer iscY0 to iscY2 if  power steering pump is off???  
            ;--------------------------------------------------------
L1417       brset   port3Snap1, #$08, L1418 ; Bail if power steering pump is activated
            ldaa    iscY0                   ;                              
            staa    iscY2                   ; iscY2 = iscY0 
                                         
            ;---------------------------------------------------------
            ; Section to compute iscStepTarg from various information
            ; Ends at L1428
            ;---------------------------------------------------------
            ;-------------------------------------------------------------------------
            ; Compute workIscStep = b = max(iscStBase, iscStBaseAc, iscStBaseCSt)
            ;-------------------------------------------------------------------------
L1418       ldab    iscStBase               ; b = iscStBase                              
            cmpb    iscStBaseAc             ;                              
            bcc     L1419                   ; Branch if iscStBase >= iscStBaseAc                             
            ldab    iscStBaseAc             ; Use min of iscStBaseAc                              
L1419       cmpb    iscStBaseCSt            ;                              
            bcc     Ne3cd                   ; Branch if max(iscStBase, iscStBaseAc) >= iscStBaseCSt                             
            ldab    iscStBaseCSt            ; Use min of iscStBaseCSt
Ne3cd       .equ    $

            ;-----------------------------------------------------------------
            ; At this point b = workIscStep
            ;
            ; Take into port3.0 signal for E931?????
            ; Basically continue calculating the max isc step to use, 
            ; this time check A/C and port3.0
            ;-----------------------------------------------------------------
#ifdef E931
            brclr   ftrimFlags, #$08, L1420 ; Bail if not (speed>24km/h and port3.0 set)                                   
            ldaa    #$53                    ; Use $53 
            brset   port3Snap1, #$10, Me3db ; Branch if A/C switch is off                                   
            ldaa    #$78                    ; Use higher value since A/C is on                           
Me3db       cba                             ;                            
            bcs     L1420                   ; Branch if we already have max value, i.e.  workIscStep > a
            tab                             ; Use new max value                           
#endif

            ;---------------------------------------------
            ; At this point b = workIscStep
            ; Compensate for barometric pressure and  
            ;---------------------------------------------
L1420       clra                            ; a = 0                          
            addb    iscStBarOff             ; d = workIscStep + iscStBarOff
            adca    #$00                    ; propagate carry                          

            ;------------------------------------------------
            ; At this point b = workIscStep
            ; Increase iscStep according to iscStStartUsed
            ;
            ; i.e. isc step adjustment upon engine startup
            ;------------------------------------------------
            addb    iscStStartUsed          ; d = workIscStep + iscStBarOff + iscStStartUsed
            adca    #$00                    ; propagate carry                          
            jsr     ovfCheck                ; Check for overflow (force result to be in b with $ff max)                              

            ;------------------------------------------------
            ; Check workIscStep for min value in iscStStall
            ;------------------------------------------------
            cmpb    iscStStall              ;                            
            bcc     L1421                   ; Branch if workIscStep + iscStBarOff + iscStStartUsed  >= iscStStall
            ldab    iscStStall              ; Use min of iscStStall                            
            bra     L1422                   ; Branch to continue                           

            ;-------------------------------------------------------------------
            ; At this point workIscStept + iscStBarOff + iscStStartUsed  >= iscStStall
            ;
            ; i.e. what we are using is already higher 
            ; than the minimum we therefore don't need 
            ; that minimum anymore...
            ;
            ; Reset iscStStall to 0 and reset flag
            ;-------------------------------------------------------------------
L1421       clr     iscStStall              ; iscStStall = 0                           
            andm    iscLrnFlags, #$df       ; Reset 00100000                              

            ;---------------------------------------------------------------------------------
            ; At this point, b = workIscStep
            ; Add the effect of power steering pump
            ;---------------------------------------------------------------------------------
L1422       brclr   port3Snap1, #$08, L1423 ; Branch if power steering pump is off                                 
#ifdef E931
            addb    #$0f                    ; b = workIscStep + $0f
#else       
            addb    #$11                    ;                           
#endif
            bcc     L1423                   ; Branch if no overflow                             
            ldab    #$ff                    ; Use max of $ff
                                        
            ;---------------------------------------------------------------
            ; increase the iscStep if the engine is running too slow 
            ; (stall conditions?) and  conditions are not good to update 
            ; isc variables (to avoid getting confused with cranking maybe?) 
            ;---------------------------------------------------------------
L1423       brclr   iscLrnFlags, #$04, L1424 ; Branch if engine is not running too slow                              
            brset   iscLrnFlags, #$10, L1424 ; Branch if conditions are good to update isc variables                             
            addb    #$22                     ; b = workIscStep + $22
            bcc     L1424                    ; Branch if no overflow                              
            ldab    #$ff                     ; Use max of $ff                                    

            ;-------------------------------------------------------------------
            ; Compute temp3 = workIscStep + (iscm/256 - $80) + (iscYn - $80)
            ;                 workIscStep'+ iscStBarOff + (iscm/256 - $80) + (iscYn - $80)
            ; This is isc step we are going to use if engine is running
            ;-------------------------------------------------------------------
L1424       jsr     iscCalc3                ; b = workIscStep + (iscm/256 - $80)
            jsr     iscCalc4                ; b = workIscStep + (iscm/256 - $80) + (iscYn - $80) 
            stab    temp3                   ; temp3 =  workIscStep + (iscm/256 - $80) + (iscYn - $80)

            ;---------------------------------------------------------------
            ; Compute temp2 = L2031(ect) + iscStBarOff + (iscm/256 - $80)
            ; This is isc step we are going to use if the engine is notRotating
            ;---------------------------------------------------------------
            ldx     #L2031                  ; x points to L2031                               
            jsr     interpEct               ; b = L2031(ect)                                   
            addb    iscStBarOff             ; b = L2031(ect) + iscStBarOff                                    
            bcc     L1425                   ; Branch if no overflow                             
            ldab    #$ff                    ; overflow, use max
L1425       jsr     iscCalc3                ; b = L2031(ect) + iscStBarOff + (iscm/256 - $80)
            stab    temp2                   ; temp2 = L2031(ect) + iscStBarOff + (iscm/256 - $80)

            ;-----------------------------------------------------------------------------
            ; Compute iscStTargSpec = temp2 + (iscYn - $80) 
            ;                       = L2031(ect) + iscStBarOff + (iscm/256 - $80) + (iscYn - $80) 
            ;
            ; This is isc step we are going to use if engine is starting to crank
            ;-----------------------------------------------------------------------------
            jsr     iscCalc4                ; b = L2031(ect) + iscStBarOff + (iscm/256 - $80) + (iscYn - $80) 
            jsr     iscStepMaxFunc          ; apply max to b                                      
            stab    iscStTargSpec           ; iscStTargSpec = L2031(ect) + iscStBarOff + (iscm/256 - $80) + (iscYn - $80) 

            ;-----------------------------------------------------------------------
            ; At this point,
            ;
            ;      temp3 = workIscStep' + iscStBarOff  + (iscm/256 - $80) + (iscYn - $80)
            ;          b = L2031(ect)   + iscStBarOff  + (iscm/256 - $80) + (iscYn - $80)
            ;      temp2 = L2031(ect)   + iscStBarOff  + (iscm/256 - $80)
            ;
            ; Now decide which value we are going to use 
            ; as working isc step  either b, temp2 or temp3
            ; Not sure why engine state is taken from a mix of state1 and iscLrnFlags???
            ;-----------------------------------------------------------------------
            brclr   iscLrnFlags, #$01, L1427 ; Branch to use temp3 if engine is not (notRotating or startingToCrank), runnning, normally or not...
            brclr   state1, #$10, L1428      ; Branch to use iscStTargSpec (already loaded in b) if notRotating clear, only startingToCrank left??? 
            ldab    temp2                    ; notRotating, use temp2
            bra     L1428                    ;                              
L1427       ldab    temp3                    ; use temp3

            ;-------------------------------------------------------------------------
            ; At this point b contains the working isc step that we have been
            ; updating/calculating for a while now, apply a max to it and store it 
            ; in iscStepTarg, this is the is isc step target...
            ;-------------------------------------------------------------------------
L1428       jsr     iscStepMaxFunc          ; apply max to b                                       
            stab    iscStepTarg             ; iscStepTarg
                                               
            ;--------------------------------------------
            ; Section to update iscYn and iscm variables
            ;--------------------------------------------
            ;------------------------------------------------------------------------------
            ; Check if a bunch of conditions are met to update the isc learning variables
            ;------------------------------------------------------------------------------
            brclr   iscLrnFlags, #$10, L1431 ; Bail if conditions are not good to update isc variables                              
            ldab    iscStepMax               ; b = iscStepMax                                  
            ldaa    iscStepTarg              ; a = iscStepTarg                                   
            beq     L1431                    ; bail if iscStepTarg = 0
            cba                              ;                             
            beq     L1431                    ; bail if iscStepTarg = iscStepMax
            brset   port3Snap1, #$08, L1431  ; bail if power steering pump is on                                   
            brset   iscLrnFlags, #$01, L1431 ; bail if notRotating or startingToCrank                               
            ldaa    T0p5_crCold              ; a = T0p5_crCold                                    
            bne     L1431                    ; bail if timer not expired                              
            ldaa    ectFiltered              ; a = ectFiltered                                   
            cmpa    #$1c                     ; 86degC                             
            bcc     L1431                    ; bail if temperature(ectFiltered) <= 86degC                             
            brset   port4Snap, #$10, L1431   ; Bail if timing terminal grounded                                   
            ldaa    iscStStartUsed           ; a = iscStStartUsed                              
            bne     L1431                    ; Bail if iscStStartUsed != 0                             
            brclr   port5, #$10, L1431       ; Bail if fuel pressure solenoid activated                               

            ;-----------------------------------------------------------
            ; All the conditions are met, update iscm and iscYn at 1 Hz
            ;-----------------------------------------------------------
            ;------------------------------------------
            ; First check if time has come to update 
            ; variables and then re-init timer 
            ;------------------------------------------
            ldaa    T40_iscLrn              ; a = T40_iscLrn                              
            bne     L1431                   ; Bail to exit subr. if timer T40_iscLrn not expired (time has not come yet...)                            
            ldaa    #$28                    ; Timer is expired, a = 1sec                            
            staa    T40_iscLrn              ; re-init T40_iscLrn to 1 sec                              

            ;-----------------------------------------
            ; Get current pointers and compute 
            ; newIscm = old iscm + 3 * (iscYn - $80)
            ;-----------------------------------------
            jsr     iscPointers             ; have x point to isc0 or isc1 and have y point to iscY0, iscY1 or iscY2                                
            ldd     #$0180                  ; d = $0180                              
            std     temp2                   ; temp2:temp3 = $0180                             
            ldaa    #$03                    ; a = $03                             
            ldab    $00,y                   ; b = iscYn, y = y + 1                              
            decy                            ; y = y - 1  
            mul                             ; d = 3 * iscYn                             
            subd    temp2                   ; d = 3 * (iscYn - $80)                              
            addd    $00,x                   ; d = iscm + 3 * (iscYn - $80)                             
            jsr     iscMinMax               ; Apply min and max to d                                
            std     temp1                   ; temp1:temp2 = newIscm = iscm + 3 * (iscYn - $80)                             

            ;---------------------------------------------------
            ; Compute newIscYn = newIscm + 3 * (iscYn - $80)
            ;---------------------------------------------------
            tab                             ; b = newIscm/256                            
            ldaa    $00,y                   ; a = iscYn, y = y + 1                             
            decy                            ; y = y - 1                             
            subb    $00,x                   ; b = newIscm/256 - iscm/256                              
            bcc     L1429                   ; Branch to continue if newIscm >= old iscm
                                     
            ;---------------------
            ; newIscm < old iscm
            ;---------------------
            negb                            ; b = (iscm - newIscm)/256                              
            aba                             ; a = iscYn + (iscm - newIscm)/256
            bcc     L1430                   ; Branch if no overflow                             
            ldaa    #$ff                    ; Use max of $ff                            
            bra     L1430                   ; Branch to store           
                              
            ;----------------------
            ; newIscm >= old iscm
            ;----------------------
L1429       sba                             ; a = iscYn - (newIscm - iscm)/256
            bcc     L1430                   ; branch if no underflow                             
            clra                            ; Use min of 0                            

            ;---------------------------------------------------------
            ; At this point 
            ;               a = newIscYn 
            ;   [temp1:temp2] = newIscm
            ;
            ; Where
            ;
            ;     newIscm = oldIscm + 3 * (oldIscYn - $80)
            ;
            ;                | oldIscYn + (oldIscm - newIscm)/256 if newIscm < oldIscm
            ;     newIscYn = |
            ;                | oldIscYn - (newIscm - oldIscm)/256 if newIscm >= oldIscm
            ;
            ;---------------------------------------------------------
L1430       staa    $00,y                   ; Update iscYn with new value
            ldd     temp1                   ; d = newIscm
            std     $00,x                   ; Update iscm with new value
L1431       rts                             ;                             



;******************************************************************
;
; ISC step calculation
;
;    input:  A = step
;    output: A =(~step & 7F)
;
;            (~step & 7F) stored in iscStepCom 
;             step stored in iscStepCurr
;
;
;******************************************************************
iscStepComp pshb                            ; st0 = val                             
            tab                             ; b = step                            
            coma                            ; a = ~step                             
            anda    #$7f                    ; a = ~step & $7f                             
            std     iscStepCom              ; iscStepCom = ~step & $7f, iscStepCurr = step
            pulb                            ; b = val                             
            rts                             ;                             



;******************************************************************
;
; Increase the value of T40s_iscStable timer if the 
; new value is higher than the current one
; 
; T40s_iscStable = max(T40s_iscStable, b)
;
;******************************************************************
updIscStableTimer   
            cmpb    T40s_iscStable  ;                                  
            bcs     L1434                   ; Branch if b < T40s_iscStable                             
            stab    T40s_iscStable          ; Use new higher value                                  
L1434       rts                             ;                             



;******************************************************************
;
;
; b = min(b,iscStepMax)
;
;
;******************************************************************
iscStepMaxFunc cmpb    iscStepMax                                                 
               bcs     L1436                                                 
               ldab    iscStepMax                                                 
L1436          rts                                                          



;******************************************************************
;
; Input:
;       b = val1
;
;
;******************************************************************
iscCalc3    stab    temp1                   ; temp1 = val1                             
            bsr     iscPointers             ; x points to iscm; y points to iscYn                                 
            ldd     $00,x                   ; d = iscm                             
            bsr     iscMinMax               ; apply min and max, d = ...                                  
            tab                             ; b = iscm/256                             
            clra                            ; a = 0                           
            addb    temp1                   ; b = iscm/256 + val1                             
            rola                            ; propagate carry, d = iscm/256 + val1                             
            bra     L1445                   ; go to subtract $80 with min check and then make sure result fits in b (max of $ff)                             


;******************************************************************
;
; ISC step related, apply min and max to D
;
; Input:
;       d = val
; Output:
;       d = max($6c00, min($b000, val))
;******************************************************************
iscMinMax   cmpd    #$b000                   ;                              
            bcs     L1439                    ; Branch if d < $b000                             
            ldd     #$b000                   ; Use max of $b000                             
L1439       cmpd    #$6c00                   ;                              
            bcc     L1440                    ; Branch if d >= $6c00                            
            ldd     #$6c00                   ; Use min of $6c00                             
L1440       rts                              ;                            



;******************************************************************
;
; Get current pointers to ISC step learning variables 
;
;        input: none (port3Snap1 is used)
;       output: X points to isc0 if A/C switch off, isc1 otherwise
;               Y points to iscY0, iscY1 or iscY2
;
;           A/C switch   PS pump        x         y
;              off         off        isc0     iscY0
;              off         on         isc0     iscY2
;              on          off        isc1     iscY1
;              on          on         isc1     iscY2
;
;******************************************************************
iscPointers ldx     #isc0                    ; x points to isc0                               
            ldy     #iscY0                   ; y points to iscY0                             
            brset   port3Snap1, #$10, L1442  ; Branch if A/C switch off                                   
            inx                              ;                            
            inx                              ; x points to isc1                           
            incy                             ; y points to iscY1                            
L1442       brclr   port3Snap1, #$08, L1443  ; Branch if power steering pump is deactivated?                                  
            ldy     #iscY2                   ; y points to iscY2                             
L1443       rts                              ;                            



;******************************************************************
;
; Input:
;       b = val
;
;
;******************************************************************
iscCalc4    bsr     iscPointers             ; x points to iscm; y points to iscYn                                 
            clra                            ; a = 0                             
            addb    $00,y                   ; d = val + iscYn                              
            adca    #$00                    ; propagate carry                            
L1445       subd    #$0080                  ; d = val + iscYn -$80                               
            bcc     L1446                   ; Branch if no underflow                             
            clra                            ;                             
            clrb                            ; Use min of 0                            
L1446       jmp     ovfCheck                ; Check that result fits in b ($ff max)                                 
            



;******************************************************************
;
; Initialize ISC iscYn variables
;
; E931:
;
;    iscY0 = $86
;    iscY1 = $8a
;    iscY2 = $86
;
; E932:
;
;    iscY0 = $86     or   iscY0 = $83 
;    iscY1 = $8a          iscY1 = $83 
;    iscY2 = $86          iscY2 = $83 
;
;******************************************************************
iscYnInit   .equ    $
#ifdef E931
            ldaa    #$86                                               
            ldab    #$8a                                               
#else
            ldaa    #$83                                                 
            tab                                                          
            brclr   port3Snap1, #$20, L1448                                     
            ldaa    #$86                                                 
            ldab    #$8a                                                 
#endif

L1448       staa    iscY0                                                 
            staa    iscY2                                                 
            stab    iscY1                                                 
            rts                                                          



;******************************************************************
;
;
; Sensor check related table, 
; correspond one for one to table at t_snsrChk
; Each entry is the bit to set/reset in the faulth:faultl 
; for the corresponding sensor
;
;
;******************************************************************
t_snsrChkBit  .word   $0200, $4000, $8000, $0001    
              .word   $0008, $0010, $0040, $2000    
              .word   $0004, $0400, $0800, $0002    



;****************************************************************
;
; Used for output of error codes to test connector
;
; in order: o2   maf  iat  tps  N/A   ect  cas   tdc    (high fault, $01, $02, $04, $08, $10, $20, $40, $80)
;           vss  bar  knk  inj  fuel  egr  coil  N/A    (low fault,  $01, $02, $04, $08, $10, $20, $40, $80)
;
; Format: 
;
;       high nibble = number of "long pulse" to output (max of 7?)
;        low nibble = number of "short pulse" to output (max of 15?)
;
;****************************************************************
t_snsrChkCode .byte   $11, $12, $13, $14, $15, $21, $22, $23, $24, $25, $31, $41, $42, $43, $44, $00



;****************************************************************
;
; Sensor check subroutine vectors
;
;****************************************************************
t_snsrChk   .word   test_maf,    test_cas,    test_tdc,    test_reed  
            .word   test_inj,    test_fpump,  test_coil,   test_ect  
            .word   test_knock,  test_iat,    test_tps,    test_baro  



;****************************************************************
;
; Actuator activate lookup table (OBD command processing)
;
;****************************************************************
t_obdActMask       .byte   $20, $10, $08, $04, $01, $02



;****************************************************************
;
; Injector disable lookup table (OBD command processing)
;
;****************************************************************
t_obdInjMask       .byte   $fb, $fd, $f7, $fe      



;******************************************************************
;
;
; Fourth subroutine
;
;
;******************************************************************
            ;--------------------------------------------------
            ; Reset a few things (most fault codes, etc)
            ; if ECU power has been on for less than 0.5 sec
            ;--------------------------------------------------
subroutine4 ldaa    T2_EcuPower             ;                             
            adda    #$01                    ;                             
            bcc     L1454                   ; Branch if its been more than 0.5sec since ECU power has been on
            andm    validFlags, #$f9        ; Reset o2 and egrt "sensor condition determined" flags
            orm     validFlags, #$01        ; set flag indicating no CAS interrupt received for a long time                               
            andm    faultHi, #$01           ; Reset all current faults but o2 sensor bit
            andm    faultLo, #$20           ; Reset all current faults but egrt sensor bit
            ldaa    #$08                    ;                             
            staa    T2_snsrChk              ; re-init T2_snsrChk with 4 sec                             
            ldaa    #$ff                    ;                             
            staa    T2_stCrank              ; re-init T2_stCrank with max value (127.5sec)                             
            andm    state2, #$ef            ; Reset ECT related flag???                                

            ;------------------------------------
            ; Set flag if engine not rotating
            ;------------------------------------
L1454       ldaa    T40_engRot                                                 
            bne     L1455                   ; Branch if engine rotating                              
            orm     validFlags, #$01        ; Engine not rotating (or very slowly) set flag                                
            bra     L1458                   ; Branch to continue
                                                          
            ;------------------------------------------------------
            ; If the engine is startingToCrank or was not rotating 
            ; the last time we were here and is now rotating                                
            ;
            ; Update ectStCrank and related timers, the ect when
            ; we started cranking...
            ;------------------------------------------------------
L1455       brset   validFlags, #$01, L1456 ; Branch if engine was not rotating the last time we checked                               
            brclr   state1, #$01, L1458     ; Bail if startingToCrank clear
L1456       andm    validFlags, #$fe        ;  startingToCrank or was not rotating the last time we were here and is now rotating                                
            ldaa    ectFiltered             ;                                    
            staa    ectStCrank              ; ectStCrank = ectFiltered                              
            ldab    #$ff                    ;                             
            stab    T2_stCrank              ; T2_stCrank = $ff  (127.5sec)                            
            stab    T0p5_crank2             ; T0p5_crank2 = $ff  (510sec)                             
            ldaa    ectRaw                  ;                               
            ldab    #$5a                    ; 180sec                            
            cmpa    #$1c                    ; 86 degC                            
            bls     L1457                   ; Branch if temperature(ectRaw)>= 86degC                              
            ldab    #$b4                    ; 360 sec                            
L1457       stab    egrtTimerThr            ; egrtTimerThr = $5a or $b4 (180sec or 360sec depending on ect)                              

            ;-------------------------------------------------
            ; Section performing the sensor check functions..
            ;-------------------------------------------------
            ;--------------------------------------------------------------------------
            ; Loop sensrChkIdx from 0 to 7 if T2_stCrank (startingToCrank) started counting 
            ; less than 60 sec ago (only first 8 sensor tests are performed,
            ; the most important ones I suppose to start the car, except for reed 
            ; switch, safety maybe?) else loop at 12 (all tests are performed)
            ;--------------------------------------------------------------------------
L1458       ldaa    #$08                    ; a = $08                             
            ldab    T2_stCrank              ; b = T2_stCrank                             
            addb    #$78                    ; b = T2_stCrank + $78   (60sec)                         
            bcs     L1459                   ; Branch if T2_stCrank started counting less than 60 sec ago
            adda    #$04                    ; a = $0c                           
L1459       ldab    sensrChkIdx             ; b = sensrChkIdx                              
            cba                             ;                             
            bhi     L1460                   ; Branch to start checking if sensrChkIdx < $0c or $08                             

            ;-------------------------------------------------
            ; sensrChkIdx >= $0c or $08 
            ; re-init T2_snsrChk to 4 sec and sensrChkIdx to 0
            ;-------------------------------------------------
            ldaa    #$08                    ;                             
            staa    T2_snsrChk              ; T2_snsrChk = 8 (4 sec)                            
            clrb                            ;                             
            stab    sensrChkIdx             ; sensrChkIdx = 0                             

            ;----------------------------------------------------------
            ; Call the sensor check rountine according to sensrChkIdx 
            ;----------------------------------------------------------
L1460       aslb                            ; b = 2*sensrChkIdx (2 bytes per address...)                            
            ldx     #t_snsrChk              ; x = t_snsrChk
            abx                             ; x = t_snsrChk + 2*sensrChkIdx                            
            ldy     $00,x                   ; y points to sensor check function                              
            ldx     #t_snsrChkBit           ; x = t_snsrChkBit (sensor "fault bit position" table)
            abx                             ; x = t_snsrChkBit + 2*sensrChkIdx                           
            clrb                            ; b = 0                            
            jsr     $00,y                   ; call sensor check subroutine                              
            tstb                            ;                             
            beq     L1462                   ; Branch if no error found                              
            bpl     L1463                   ; Branch if inconclusive                             

            ;------------------------------------------------------
            ; Sensor check returned negative, error is detected 
            ; 
            ; Check if T2_snsrChk is expired, which would mean we have 
            ; been stuck on testing the same sensor for 4 sec and 
            ; it never worked properly...)
            ;------------------------------------------------------
            ldd     $00,x                   ; [a:b] = t_snsrChkBit(sensrChkIdx)
            tst     T2_snsrChk              ;                                                                                                   
            beq     L1461                   ; branch if T2_snsrChk is 0 (more than 4 sec elapsed since sensrChkIdx was reset to 0)

            ;------------------------------------------------------
            ; T2_snsrChk is not expired, don't set the error flags but 
            ; if it they were already set increase sensrChkIdx
            ; (meaning this sensor was already detected as bad
            ; with a 4 sec check, don't do it again for that 
            ; sensor, go to the next one)
            ;------------------------------------------------------
            anda    faultHi                 ; 
            bne     L1463                   ; Branch to increase sensrChkIdx if error bit was already set (if it was located in faultHi)                                                                                               
            andb    faultLo                 ;                                                                                                  
            bne     L1463                   ; Branch to increase sensrChkIdx if error bit was alrready set (if it was located in faultLo)                                                                                               
            bra     L1464                   ; Error bit was not already set, don't change sensrChkIdx (check it agaian next time)                                                                                               

            ;-----------------------------------------------------------------------
            ; More than 4 sec elapsed since sensrChkIdx was reset to 0
            ; (this means that we have been stuck on testing the same sensor
            ; for 4 sec and it never worked properly...)
            ;
            ; Set the error flags and increase sensrChkIdx
            ;-----------------------------------------------------------------------
L1461       oraa    faultHi                ; Set the error bit if located in faultHi                                                                                       
            orab    faultLo                ; Set the error bit if located in faultLo                                                                                                  
            std     faultHi                ; Update faultHi:faultLo
            oraa    stFaultHi              ; Set the error bit if located in stFaultHi
            orab    stFaultLo              ; Set the error bit if located in stFaultLo
            std     stFaultHi              ; Update stFaultHi:stFaultLo
            bra     L1463                  ; Branch to increase sensrChkIdx                                                                                               

            ;---------------------------------------------------
            ; Sensor check returned zero, no error, reset bit
            ;---------------------------------------------------
L1462       ldd     $00,x                   ; [a:b] = t_snsrChkBit(sensrChkIdx)
            coma                            ; complement all bits                            
            comb                            ; complement all bits                            
            anda    faultHi                 ; reset the bit if it was in faultHi 
            andb    faultLo                 ; reset the bit if it was in faultLo                               
            std     faultHi                 ; Update faultHi:faultLo                                

            ;------------------------------------------------------
            ; Go to next sensor and re-init T2_snsrChk to 4 sec 
            ;------------------------------------------------------
L1463       inc     sensrChkIdx             ; Increment index (go to next sensor check subroutine next time)                                    
            ldaa    #$08                    ; 4 sec                            
            staa    T2_snsrChk              ; re-init timer to 4 sec                                  

            ;-------------------------------------------------------------------------------
            ; Section to verify the O2 sensor under specific conditions 
            ;-------------------------------------------------------------------------------
            ;-------------------------------------------------------------------------------
            ; First check if o2Raw indicate rich or lean, set a flag in b for now
            ;-------------------------------------------------------------------------------
L1464       clrb                            ; assume we are running lean, b = 0                            
            ldaa    o2Raw                   ; a = o2Raw                             
            cmpa    #$1f                    ;                             
            bcs     L1465                   ; Branch if o2Raw < 0.6V (lean)                             
            orab    #$80                    ; Set flag indicating we are running rich
                                        
            ;-------------------------------------------------------------------------------
            ; Now check if all the conditions are met to do the verfication
            ;
            ;       engine has been running for more than 180sec
            ;       baro sensor value is reliable
            ;       no fault code on baro, coil, iat, ect, cas
            ;       ectRaw and iatRaw are within acceptable range
            ;       temperature(ectRaw) > 86degC
            ;       temperature(iatRaw) > 0degC
            ;       temperature(iatRaw) < 55degC
            ;       engine is running normally (no fuel cut, etc..)
            ;       airVolTB < $68 
            ;       airVolTB > $33
            ;       rpm31 < 4000
            ;       rpm31 > 2000
            ;       all conditions for closed loop mode are met
            ;
            ;-------------------------------------------------------------------------------
L1465       ldaa    T0p5_crank2             ; a = T0p5_crank2                              
            adda    #$5a                    ;                             
            bcs     L1467                   ; Bail if its been less than 180sec since engine started rotating                             
            ldaa    T40_baro                ; T40_baro                                 
            bne     L1467                   ; Bail if T40_baro not zero (meaning baro sensor value is not reliable)
            brset   faultLo, #$42, L1467    ; Bail if errors on baro or coil                                 
            brset   faultHi, #$26, L1467    ; Bail if errors on iat, ect or cas                                 
            brset   state2, #$03, L1467     ; Bail ifectRaw or iatRaw out of acceptable range                                
            ldaa    ectRaw                  ; a = ectRaw                              
            cmpa    #$1c                    ;                             
            bcc     L1467                   ; Bail if temperature(ectRaw) <= 86degC                             
            ldaa    iatRaw                  ; a = iatRaw                               
            cmpa    #$b3                    ;                             
            bcc     L1467                   ; Bail if temperature(iatRaw) <= 0degC                              
            cmpa    #$41                    ;                             
            bls     L1467                   ; Bail if  temperature(iatRaw) >= 55degC                               
            brset   state1, #$1f, L1467     ; Bail if engine not running normally (i.e. notRotating or startingToCrank or rotatingStopInj or runningFast or no pulse accumulator interrupts received )
            ldaa    airVolTB                ; a = airVolTB 
#ifdef E931
            cmpa    #$68                    ;                             
            bcc     L1467                   ; Bail if airVolTB >= $68 
            cmpa    #$33                    ;                             
#else
            cmpa    #$90                    ;                             
            bcc     L1467                   ;                              
            cmpa    #$1a                    ;                             
#endif
            bls     L1467                   ; Bail if airVolTB <= $33 
            ldaa    rpm31                   ; a = rpm31                              
            cmpa    #$80                    ;                             
            bcc     L1467                   ; Bail if rpm31 >= 4000                              
            cmpa    #$40                    ;                             
            bls     L1467                   ; Bail if rpm31 <= 2000                              
            brclr   closedLpFlags, #$02, L1467   ; Bail if not all conditions for closed loop mode are met

            ;---------------------------------------------------------
            ; All the conditions are met
            ; At this point, b = $80 if o2Raw is rich, $00 otherwise
            ;---------------------------------------------------------
            tba                             ; a = $80 if o2Raw rich else $00                               
            adda    validFlags              ; a = validFlags + ($80 or $00)                              
            bmi     L1466                   ; Branch if running rich (validFlags + ($80 or $00) > $80 only if o2Raw>=0.6V above...)                             

            ;-------------------------------
            ; Running lean (o2Raw < 0.6V)
            ;-------------------------------
            ldaa    T2_o2Chk                ; a = T2_o2Chk                            
            bne     L1468                   ; Branch if timer not expired, its been less than 30sec since all conditions were met and we are running lean                            
            brset   validFlags, #$02, L1468 ; Branch if o2 sensor condition already determined (no need to check further)

            ;------------------------------------------------------
            ; Timer is expired and the o2 sensor condition is not 
            ; already determined. Since we have been running lean
            ; for over 30sec, we know the sensor is bad...
            ;
            ; Set the flag indicating the o2 sensor conditions was
            ; determined, and increment o2BadCnt (with max of 255) to
            ; indicate we have an error condition
            ; Note that o2BadCnt increase by 1 max every time 
            ; the ECU is turned on (which resets validFlags.1)
            ;------------------------------------------------------
            orm     validFlags, #$02        ; Set flag indicating o2 sensor condition was checked (bad in this case)                               
            inc     o2BadCnt                ; o2BadCnt = o2BadCnt + 1                              
            bne     L1468                   ; Branch to continue if o2BadCnt != 0                              
            dec     o2BadCnt                ; o2BadCnt equals 0, go back to 255                               
            bra     L1468                   ; branch to continue                             

            ;-----------------------------------------------------------------
            ; Running rich (o2Raw >= 0.6V)
            ; As soon as we are running rich we know the sensor 
            ; is good, clear fault and set flag indicating o2 sensor 
            ; conditions was determined (good in this case)
            ;-----------------------------------------------------------------
L1466       clr     o2BadCnt                ; o2BadCnt = 0                               
            orm     validFlags, #$02             ; Set flag indicating o2 sensor condition was checked (ok in this case)                               

            ;-------------------------------
            ; Re-init timer T2_o2Chk to 30sec
            ;-------------------------------
L1467       ldaa    #$3c                    ; 30sec                             
            staa    T2_o2Chk                ;                             

            ;------------------------------------------------------------
            ; Update validFlags.7 rich/lean flag with current o2 conditions
            ;------------------------------------------------------------
L1468       andm    validFlags, #$7f             ; Reset rich/lean flag 
            addb    validFlags                   ; Add current rich/lean flag (set to 1 if rich)                            
            stab    validFlags                   ; Update validFlags                             

            ;---------------------------------------------------------------------------
            ; if o2BadCnt >= 1, set o2 fault code in current and stored fault variables
            ;---------------------------------------------------------------------------
            ldaa    o2BadCnt                ;                               
            cmpa    #$01                    ;                             
            bcs     L1469                   ; Branch to no o2 fault if o2BadCnt=0                             
            orm     faultHi, #$01           ; set oxygen sensor fault code?
            orm     stFaultHi, #$01         ;                                    
            bra     L1470                   ;                              

            ;------------------------------------------------------------
            ; Reset o2 fault code in only current fault variables
            ;------------------------------------------------------------
L1469       andm    faultHi, #$fe           ; Clear oxygen sensor fault code

            ;-------------------------------------------------------------------------------
            ; Check if all the conditions are met to test the egrt sensor validity
            ;
            ;       more than ($5a or $b4)/0.5 sec have elapsed since engine started rotating                             
            ;       baro sensor value is reliable
            ;       no fault code on baro, coil, iat, ect, cas
            ;       ectRaw and iatRaw are within acceptable range
            ;       temperature(ectRaw) > 86degC
            ;       temperature(iatRaw) < 55degC
            ;       baroRaw > 0.92bar
            ;       rpm31 < 3500
            ;       rpm31 > 2094
            ;       airVol < L2048(rpm)
            ;       airVol > L2047(rpm)
            ;
            ;-------------------------------------------------------------------------------
L1470       ldaa    egrtTimerThr            ; a = egrtTimerThr                             
            adda    T0p5_crank2             ;                               
            bcs     L1474                   ; Bail if less than ($5a or $b4)/0.5 sec have elapsed since engine started rotating                             
            ldaa    T40_baro                ;                                 
            bne     L1474                   ; Bail if T40_baro not zero (meaning baro sensor value is not reliable)
            brset   faultLo, #$42, L1474    ; Bail if errors on baro or coil                                      
            brset   faultHi, #$26, L1474    ; Bail if errors on iat, ect or cas                                  
            brset   state2, #$03, L1474     ; Bail ifectRaw or iatRaw out of acceptable range                                
            ldaa    ectRaw                  ;                               
            cmpa    #$1c                    ;                             
            bcc     L1474                   ; Bail if temperature(ectRaw) <= 86degC                             
            ldaa    iatRaw                  ;                               
            cmpa    #$42                    ;                             
            bls     L1474                   ; Bail if  temperature(iatRaw) >= 55degC                             
            ldaa    baroRaw                 ;                                
            cmpa    #$bd                    ;                             
            bcs     L1474                   ; Bail if baroRaw < 0.92bar                               
            ldaa    rpm31                   ;                              
            cmpa    #$70                    ;                             
            bcc     L1474                   ; Bail if rpm >=3500                              
            cmpa    #$43                    ;                             
            bls     L1474                   ; Bail if rpm <= 2094                              
            ldx     #L2048                  ;                               
            jsr     interp16rpm             ; b = L2048(rpm)                                    
            cmpb    airVol                  ;                               
            bls     L1474                   ; Bail if airVol >= L2048(rpm)                               
            ldx     #L2047                  ;                               
            jsr     interp16rpm             ; b = L2047(rpm)                                   
            cmpb    airVol                  ;                               
            bcc     L1474                   ; Bail if airVol <= L2047(rpm)                              

            ;------------------------------------------
            ; All basic condition are met,
            ; bail if T2_egrtChk > 10
            ;------------------------------------------
            ldaa    T2_egrtChk              ;                             
            cmpa    #$0a                    ;                             
            bhi     L1478                   ; Bail if T2_egrtChk > 10 ????      
                                   
            ;----------------------------------------------------
            ; All basic condition are met and  T2_egrtChk <= 10
            ; Check the temperature indicated by the egrt 
            ; sensor and branch accordingly 
            ;----------------------------------------------------
            ldaa    #$05                    ;                             
            cmpa    egrtRaw                 ;                                
            bhi     L1477                   ; Branch if temperature(egrtRaw) > 307degCC (error, too hot)                            
            ldx     #L2046                  ;                               
            jsr     iatCInterp              ; b = L2046(iat)                                  
            cmpb    egrtRaw                 ;                                
            bcs     L1477                   ; Branch if temperature(egrtRaw) < L2046(iat) (error, too cold)                               

            ;--------------------------------------------------------
            ; At this point we know the egrt sensor is good 
            ; clear fault and set flag indicating sensor condition
            ; was determined (good in this case)
            ;--------------------------------------------------------
            clr     egrtBadCnt              ; egrtBadCnt = 0, no fault                               
            orm     validFlags, #$04             ; Set flag indicating sensor condition was checked (ok in this case)                               
            clra                            ; a = 0                            
            bra     L1475                   ; Branch to set timer to 5 sec such that we continously check the sensor                           

            ;----------------------------------------
            ; Reset T2_egrtChk timer to 20 sec and bail
            ;----------------------------------------
L1474       ldaa    #$1e                    ; a = 15sec                            
L1475       adda    #$0a                    ; a = a + 5sec                            
            bcc     L1476                   ; Branch if no overflow                             
            ldaa    #$ff                    ; Use max of $ff                            
L1476       staa    T2_egrtChk              ; Update T2_egrtChk                            
            bra     L1478                   ; Bail                             

            ;----------------------------------------------------------------------------------
            ; At this point we found that the sensor temperature is out of range (bad sensor)
            ;----------------------------------------------------------------------------------
L1477       ldaa    T2_egrtChk            ; a = T2_egrtChk                             
            bne     L1478                   ; Branch if timer not expired                             
            brset   validFlags, #$04, L1478      ; Branch if egrt sensor condition already determined

            ;--------------------------------------------------------------------------
            ; Sensor is bad, timer is expired and sensor condition not yet determined
            ;
            ; Set flag indicating sensor condition was determined (bad in this case)
            ; and increment egrtBadCnt (255 max) to indicate we have an error condition 
            ; Note that egrtBadCnt increase by 1 max every time the ECU is turned off/on
            ; (which resets validFlags.1)
            ;--------------------------------------------------------------------------
            orm     validFlags, #$04             ; Set flag                               
            inc     egrtBadCnt              ; egrtBadCnt = egrtBadCnt + 1                              
            bne     L1478                   ; Bail if egrtBadCnt != 0                               
            dec     egrtBadCnt              ; egrtBadCnt equals 0, go back to 255                              

            ;---------------------------------------------------------------------------
            ; if egrtBadCnt >= 2, set egrt fault code in current and stored fault variables
            ;
            ; egrtBadCnt >= 2 only if the ECU is turned off and then on again 
            ;---------------------------------------------------------------------------
L1478       ldaa    egrtBadCnt              ;                               
            cmpa    #$02                    ;                             
            bcs     L1479                   ; Branch if egrtBadCnt < 2
            orm     faultLo, #$20           ; Set egrt sensor fault flag                                 
            orm     stFaultLo, #$20         ; Set egrt sensor fault flag                                   
            bra     L1480                   ;                              

            ;------------------------------------------------
            ; Reset egrt fault code in current fault variable
            ;------------------------------------------------
L1479       andm    faultLo, #$df           ;                                  

            ;---------------------------------------------------------------------------
            ; Reset egrt errors and fault codes if vehicle is not for California 
            ;---------------------------------------------------------------------------
L1480       brset   config1, #$04, L1481    ; Bail if California car                                
            clr     egrtBadCnt              ; reset egrt error count                               
            andm    stFaultLo, #$df         ; Reset egrt stored fault code                                   
            andm    faultLo, #$df           ; Reset egrt current fault code                                 

            ;---------------------------------------------------------------------------
            ; Reset N/A stored fault codes (fault codes don't correspond to anything)
            ;---------------------------------------------------------------------------
L1481       andm    stFaultHi, #$ef         ;                                    
            andm    stFaultLo, #$7f         ;                                    

            ;----------------------------------------------------------------
            ; If ECU is not about to turn-off check if there are faults set
            ; and inital 5 sec "check engine light on" delay
            ;----------------------------------------------------------------
            ldaa    T40_noPower             ;                                    
            beq     L1482                   ; Branch to clear check engine light if timer expired (ECU is about to turn-off)
            ldd     faultHi                 ; d = faultHi:faultLo (current faults)                               
            anda    #$ef                    ; Reset N/A sensor fault bit                             
            bne     L1483                   ; Branch to set check engine light if any errors left in faultHi
            andb    #$7e                    ; Reset vss and baro sensor in faultLo                            
            bne     L1483                   ; Branch to set check engine light if any errors left in faultLo
            ldaa    T2_EcuPower             ;                                    
            adda    #$0a                    ;                             
            bcs     L1483                   ; Branch if its been less than 5 sec since ECU power has been on                             

            ;------------------------------------------------------------------
            ; Its been more than 5 sec since ECU power has been on
            ; and there is no fault set in faultHi:faultLo (apart from vss)
            ; and ECU in not about to turn off
            ;
            ; Clear check engine light                             
            ;------------------------------------------------------------------
L1482       orm     port6, #$08             ; clear CE light                                                                            
            bra     L1484                   ;                                                                                             

            ;-------------------------------------------------------------
            ; Its been less than 5 sec since ECU power has been on
            ; or there are faults set in faultHi:faultLo (apart from vss) 
            ; or ECU is about to turn off
            ;
            ; Activate check engine light                             
            ;-------------------------------------------------------------
L1483       andm    port6, #$f7             ; activate CE light                                                                               


            ;-----------------------------------------------------------------
            ; Section to process diagnostic connector port commands/requests
            ;-----------------------------------------------------------------
            ;--------------------------------------------------------------
            ; Bail to "heart beat" mode section if port rx is not enabled
            ;--------------------------------------------------------------
L1484       brset   sci_scr, #$08, L1485    ; Branch if serial port rx enabled.                                                                      
            jmp     L_heartBeat             ; rx not enabled, branch to section processing heart beat code

            ;-----------------------------------------------------------
            ; rx is enabled, we are in test mode. Check if anything 
            ; is being transmited or if anything new was received
            ;-----------------------------------------------------------
L1485       brclr   sci_scr, #$20, L1486    ; Branch if transmit data register is not empty (1 = empty...)                                 
            brset   obdFlags, #$40, L1487   ; tx empty, branch if anything to process (e.g. a code was received (in interupt) and stored in obdCode)?

            ;-------------------------------------------------
            ; At this point rx enabled but tx not empty 
            ; or it is empty but there is nothing to process
            ;
            ; Reset action related registers and bail
            ;-------------------------------------------------
L1486       orm     obdInjCmd, #$3f         ; reset any injector action
            clr     obdActCmd               ; reset any actuator action
            clr     T40_obdCmd              ; Clear action timer                                                                         
            jmp     L1504                   ; Bail to rest of code                                               

            ;------------------------------------------------------------
            ; At this point we are in test mode, transmit register is 
            ; empty and a new code was received and stored in obdCode
            ; Process the new code,
            ;------------------------------------------------------------
            ;------------------------------------------
            ; Check if code is $fd (serial link test)
            ;------------------------------------------
#ifdef E931
L1487       ldaa    #$b5                    ; Default value returned if code = $fd. (serial link test)
#else
L1487       ldaa    #$b7                    ; Default value returned if code = $fd. (serial link test)
#endif
            ldab    obdCode                 ; load received OBD code                       
            cmpb    #$fd                    ;                                              
            bcs     L1490                   ; branch if code is lower than $FD             
            beq     L1496                   ; bail to send response if code is equal to $fd

            ;--------------------------------------------------------
            ; obdCode equals $fe or $ff, respond with high or low
            ; part ($fe or $ff code) of configration data (t_strap3)
            ;--------------------------------------------------------
            ldx     #t_strap3               ; x = configuration data
            tba                             ;                                              
            jsr     cfgLookup16             ;                                              
            cmpa    #$fe                    ; compare to FE                                
            xgdx                            ;
            beq     L1489                   ;
            tba                             ;
L1489       bra     L1496                   ; branch to send on serial                                    

            ;------------------------
            ; obdCode lower than $fd
            ;------------------------
L1490       cmpb    #$f1                    ;                                                             
            bcc     L1494                   ; branch if code is larger or equal to $f1                    
            cmpb    #$40                    ;                                                             
            bcs     L1491                   ; branch if code is lower than $40                            

            ;------------------------
            ; $40 <= obdCode < $f1
            ; Check if it is $ca
            ;------------------------
            cmpb    #$ca                    ;                                                             
            beq     L1493                   ; branch if code equals $ca                                    

            ;----------------------------------------------------------------------
            ; $40 <= obdCode < $f1 and it is not $ca
            ; just respond with whatever is stored in the corresponding memory
            ;----------------------------------------------------------------------
            clra                            ; a=0
            xgdx                            ; x = obdCode
            ldaa    $00,x                   ; a = whatever is in corresponding memory
            bra     L1496                   ; branch to send on serial                                    

            ;----------------------------------------------------------------------
            ; obdCode lower than $40, respond with sensor value 
            ; ($3e and $3f are converted to $3d)
            ;----------------------------------------------------------------------
L1491       ldx     #obdTable               ; x points to obdTable
            cmpb    #$3d                    ;                                                             
            bls     L1492                   ; branch if obdCode <= $3d                                         
            ldab    #$3d                    ; Use max of $3d ($3e and $3f are converted to $3d???)                     
L1492       abx                             ; x points to "sensor" address in table                                
            ldab    $00,x                   ; b = obdTable(obdCode)
            clra                            ; a = 0                                                            
            xgdx                            ; x = d = obdTable(obdCode)
            ldaa    $00,x                   ; a = sensor value
            bra     L1496                   ; branch to send on serial                                    

            ;----------------------------------------------------
            ; obdCode = $ca, clear error faults if engine is not 
            ; rotating and respond with $00
            ;----------------------------------------------------
L1493       ldaa    T40_engRot              ;                                                                                                         
            bne     L1502                   ; Don't reset fault codes if engine is rotating, we use them to run the car...                                                                     
            clra                            ;                                                                                                         
            clrb                            ;                                                                                                                                      
            std     stFaultHi               ; Erase fault codes                                                                                                                     
            std     faultHi                 ; Erase fault codes                                                                                                                     
            staa    o2BadCnt                ; Erase o2 sensor error count
            staa    egrtBadCnt              ; Erase egrt sensor error count
            clra                            ;                                                                                                                                      
            bra     L1496                   ; Branch to send $00 on serial
                                                                                                                                                      
            ;----------------------------------------------------
            ; obdCode >= $f1, this is a command/action code
            ; Check if any action is already ongoing
            ;----------------------------------------------------
L1494       ldaa    obdInjCmd               ; a = obdInjCmd            
            coma                            ; a = ~obdInjCmd           
            anda    #$3f                    ; a = ~obdInjCmd & 00111111                                                                                                                                        
            bne     L1495                   ; branch if any injector already turned-off
            brclr   obdActCmd, #$ff, L1497  ; branch to continue processing if no actuator previously activated
                                                                                                         
            ;----------------------------------------------------
            ; obdCode >= $f1 and an action is already ongoing
            ;----------------------------------------------------
L1495       ldaa    T40_obdCmd              ; 
            bne     L1497                   ; Branch if timer not expired                                                                                                                                      

            ;----------------------------------------------------
            ; Action already ongoing and timer is expired,
            ; reset all injector and actuators to normal mode and 
            ; respond with $00 (ignore new action)
            ;----------------------------------------------------
            orm     obdInjCmd, #$3f         ; set all injectors to normal operation                                                                                                                 
            clr     obdActCmd               ; clear current actuator commands                                                                                                                 
            ldaa    #$00                    ;                                                                                                                                      
L1496       jmp     L1503                   ;                                                                                                                                       

            ;-----------------------------------------------
            ; No action is ongoing or an action is ongoing 
            ; but not finished (timer not expired)
            ;
            ; continue processing new code
            ;-----------------------------------------------
L1497       cmpb    #$f6                    ;                                                                                                                                      
            bls     L1498                   ; branch if code is $f1 to $f6                                                                                                            

            ;-----------------------------------------------------------
            ; $f7 <= obdCode <= $fc, this is a turn injector off command
            ; Bail if vehicle is moving
            ;-----------------------------------------------------------
            ldaa    vssCnt1                 ; a = check speed                                                                                                                                      
            beq     L1499                   ; Branch if speed is close to 0                                                                                                                                      
            bra     L1502                   ; speed too high, bail (safety I assume)        
                                                                                                                                          
            ;----------------------------------------------------
            ; $f1 <= obdCode <= f6, this is an actuator command
            ; Bail if engine is rotating
            ;----------------------------------------------------
L1498       ldaa    T40_engRot              ; code is F1 to F6, check if "engine running"?                                                                                          
            bne     L1502                   ; bail if engine is rotating  (safety I assume)

            ;------------------------------------------------------------
            ; $f1<= obdCode <= $f6 and it is safe to perform the action
            ; continue processing command/action code
            ;------------------------------------------------------------
            ;----------------------------------
            ; Bail if any injector is already 
            ; turned-off by previous command
            ;----------------------------------
L1499       ldaa    obdInjCmd               ; a = obdInjCmd
            coma                            ; a = ~obdInjCmd
            anda    #$3f                    ; a = ~obdInjCmd & 00111111
            bne     L1504                   ; bail if any injector already off                                                                                                                

            ;----------------------------------
            ; Bail if an actuator is already 
            ; turned-on by previous command
            ;----------------------------------
            brset   obdActCmd, #$ff, L1504  ; bail if a previous action is ongoing

            ;-----------------------------------------
            ; Check if injector or actuator command
            ;-----------------------------------------
            subb    #$f7                    ; b = obdCode - $f7
            bcs     L1500                   ; Branch if obdCode < $f7 (actuator command)

            ;-------------------------------------------
            ; obdCode >=$f7, it is an injector command, 
            ; Ignore it for injectors 5 and 6
            ;-------------------------------------------
            subb    #$02                    ; b = injIndex = obdCode - $f7 - $02 = -2 to 3 range (injector 6 to 1 respectively...)
            bcs     L1502                   ; branch if code is negative (injectors 5 and 6, do nothing)                                                                           

            ;----------------------------------
            ; obdCode >=$f7, injector command
            ;----------------------------------
            ldx     #t_obdInjMask           ; x points to t_obdInjMask (table t_obdInjMask: $fb $fd $f7 $fe)                                                                                                             
            abx                             ; 
            ldaa    $00,x                   ; a = t_obdInjMask(injIndex) ($fb $fd $f7 $fe for injector 4 3 2 1 resp.-> order in nibble -> 2 4 3 1)
            clrb                            ; b = $00                                                                                                                                     
            bra     L1501                   ;     
                                                                                                                                              
            ;--------------------------------------------
            ; obdCode <$f7, it is an actuator command
            ;--------------------------------------------
L1500       addb    #$06                    ; b = actIndex = obdCode - $f7 + $06 = 0 to 5
            ldx     #t_obdActMask           ; x points to t_obdActMask: 20 10 08 04 01 02                                                                                                          
            abx                             ;                                                                                                                                      
            ldab    $00,x                   ; b = t_obdActMask(actIndex)
            ldaa    #$ff                    ; a = $ff

            ;-----------------------------------------------------------
            ; At this point, 
            ; a contains the new injector to turn off, if any 
            ; b contains the new actuator to turn on, if any 
            ;
            ; Update obdInjCmd and obdActCmd. Notice that only one 
            ; actuator is activated at a time but multiple injectors 
            ; can be turned off...
            ;-----------------------------------------------------------
L1501       sei                             ; Disable interrupts                                                                                                                                     
            anda    obdInjCmd               ; Turn off the new injector and continue turning off the existing ones
            staa    obdInjCmd               ; Update  obdInjCmd 
            stab    obdActCmd               ; Turn on the new actuator
            cli                             ;                                                                                                                                      

            ;--------------------------------------------
            ; Re-init T40_obdCmd timer to 6sec and bail
            ;--------------------------------------------
            ldaa    #$f0                    ; 6 sec
            staa    T40_obdCmd              ; T40_obdCmd = 6 sec                                                                                                                                      
            bra     L1504                   ; jump to RTS                                                                                                                           

            ;--------------------------------------------
            ; Reset any ongoing actions (injector or actuator)
            ;--------------------------------------------
L1502       orm     obdInjCmd, #$3f         ; Set all injectors to on                                                                                                                 
            clr     obdActCmd               ; Set all actuators to off                                                                                                  
            clr     T40_obdCmd              ; Clear timer
            ldaa    #$ff                    ; respond with $ff                                                                                                                                     

            ;-----------------------------------------------------------------
            ; At this point a contains the response to send on diagnostic port
            ; send it...
            ;-----------------------------------------------------------------
L1503       staa    sci_tx                  ; either FF or 00 or output value to serial port                                                                                    
            orm     obdFlags, #$80          ; set bit indicating something has been sent
            andm    obdFlags, #$bf          ; reset bit $40 since we finished processing the request

            ;---------------------------------------------
            ; Jump to rest of code (skip heart beat mode)
            ;---------------------------------------------
L1504       jmp     L1524                   ; Jump to RTS                                                                                                                           
                                                                   


;****************************************************************
;
; Used in processing the output of error codes to test connector
;
; Used to Represent the number of shift we need to apply...
;
;****************************************************************
t_errCodeShift .byte   $80, $40, $20, $10, $08, $04, $02, $01



;****************************************************************
;
; Output error codes to test connector (heart beat mode)
;
; a and b are used throughout this code to contain 
; the old/new values of errCodeProc and errCodeIdx
;
; Freakin difficult code to disassemble! 
;
;
;****************************************************************
            ;----------------------------
            ; Only execute code at 2Hz
            ;----------------------------
L_heartBeat brset   Tclocks, #$04, L1507    ; Branch if 2Hz signal set
            jmp     L1524                   ; 2Hz signal not yet set, bail 

            ;--------------------------------------------------
            ; Load basic variables and check whether 
            ; a code is currently being output to connector
            ;--------------------------------------------------
L1507       ldaa    errCodeProc             ; a = errCodeProc
            ldab    errCodeIdx              ; b = errCodeIdx                                                                                         
            tsta                            ;                             
            bne     L1508                   ; Branch if errCodeProc != 0 ( a code is currently being output)
            bitb    #$e0                    ; test 3 bit 2Hz timer...                            
            beq     L1509                   ; Branch if timer is expired (we are really finished with previous code...)
L1508       jmp     L1520                   ; Jump to continue processing the code currently being output
             
            ;---------------------------------------------------------------
            ; At this point we are not processing anything, continue trying
            ;---------------------------------------------------------------
L1509       clra                            ; a = 0                             
            staa    temp1                   ; temp1 = 0                             
L1510       ldaa    stFaultHi               ; preload a = stFaultHi                                   
            stab    temp2                   ; temp1:temp2 = errCodeIdx, notice "stab" changes zero flag for branch below...                              
            beq     L1512                   ; Branch if errCodeIdx = 0

            ;---------------------------------------------
            ; errCodeIdx > 0
            ; Check if errCodeIdx <= 8                 
            ;---------------------------------------------
            ldx     #t_errCodeShift-1       ; x points to t_errCodeShift-1                              
            subb    #$08                    ; b = errCodeIdx - 8                            
            bls     L1511                   ; Branch if errCodeIdx <= 8                             

            ;----------------------------------------------
            ; errCodeIdx > 8, current index is in low fault                 
            ;----------------------------------------------
            ldaa    stFaultLo               ; a = stFaultLo since thats what we should be using                                 
            abx                             ; x points to t_errCodeShift - 1 + (errCodeIdx - 8)                            
            ldab    $00,x                   ; b = t_errCodeShift(errCodeIdx)
            mul                             ; shift whats left to process in high part of d (in a)
            ldx     temp1                   ; x = 0:errCodeIdx
            tsta                            ; test if any fault bit set
            bra     L1513                   ; Branch 

            ;-----------------------------------------------
            ; errCodeIdx <= 8, current index is in high fault                
            ;-----------------------------------------------
L1511       addb    #$08                    ; b = errCodeIdx - 8 + 8 = errCodeIdx                           
            abx                             ; x points to t_errCodeShift-1 + errCodeIdx                           
            ldab    $00,x                   ; b = t_errCodeShift(errCodeIdx)
            mul                             ; shift whats left to process in high part of d (in a)

L1512       ldx     temp1                   ; x = 0:errCodeIdx
            tsta                            ; test if any fault bit set
            bne     L1514                   ; Branch if any fault bit were set

            ;-----------------------------------------------
            ; No fault bit set in high part, try low part now
            ;-----------------------------------------------
            ldx     #$0008                  ; new errCodeIdx x = 8                              
            ldaa    stFaultLo               ; a = stFaultLo                                  

            ;--------------------------------------------------                 
            ; At this point, a contains the error bits left (if any)
            ; to process and x is the current index error 
            ;--------------------------------------------------                 
L1513       beq     L1515                   ; branch if no error are set in what is left to process

            ;---------------------------------
            ; Loop until we find the bit
            ;---------------------------------                 
L1514       inx                             ; ++x
            lsra                            ; Shift lowest bit in carry
            bcc     L1514                   ; Loop if bit was 0                             

            ;----------------------------------------------------------------
            ; We found a bit set -> we found the next error code to output...
            ; update new errCodeProc value (in a for now) and new errCodeIdx
            ; (in a for now)
            ;----------------------------------------------------------------
            stx     temp1                   ; temp1:temp2 = newBitIndex of next code????
            ldab    temp2                   ; b = newBitIndex
            ldx     #t_snsrChkCode-1        ; x points to t_snsrChkCode-1
            abx                             ; x points to t_snsrChkCode-1 + newBitIndex
            ldaa    $00,x                   ; a = t_snsrChkCode(newBitIndex)                              
            oraa    #$80                    ; a = t_snsrChkCode(newBitIndex) | $80                            
            andb    #$1f                    ; b = newBitIndex & $1f                            
            orab    #$a0                    ; Set newBitIndex high bits (timer) to 2.5 sec
            bra     L1521                   ; Branch to set heart beat output and store a and b                             

            ;------------------------------------------------------
            ; No error found in stFaultLo, this means we are 
            ; at the end of the cycle... (we checked high part 
            ; first and then low part), restart the whole 
            ; thing from errCodeIdx=0 if errCodeIdx not already at 0
            ;------------------------------------------------------
L1515       clrb                            ; b = 0 = new value of errCodeIdx                             
            ldaa    temp2                   ; a = old errCodeIdx                             
            bne     L1510                   ; Loop back if old errCodeIdx != 0                             

            ;--------------------------------------------------------------------------
            ; errCodeIdx already at 0, there where no error during the cycle
            ; toggle heart beat sent to diagnostic port, this is the "no fault" signal
            ;--------------------------------------------------------------------------
            psha                            ; st0 = a, why, we know a=0 from test above???????????
            sei                             ; Make sure no interrupt plays with port2 while we change it
            ldaa    port2                   ;                               
            eora    #$10                    ; Toggle heart beat sent to diagnostic port?
            staa    port2                   ; Update port                             
            cli                             ;                             
            pula                            ; a = st0 = 0                               
            bra     L1523                   ; Branch to exit       
                                  
            ;----------------------------------------------------------------
            ; errCodeIdx upper 3 bit timer is expired (Branch from below)
            ; First check if there are more long pulse to ouptput
            ;----------------------------------------------------------------
L1516       bita    #$70                    ;                             
            beq     L1518                   ; Branch if no more long pulse code (errCodeProc & 01110000 = 0)                             

            ;-------------------------------------
            ; There are more long pulse to output
            ;-------------------------------------
            suba    #$10                    ; decrement the number of long pulse by 1
            andb    #$1f                    ; reset timer to 0 (upper 3 bits)                            
            orab    #$80                    ; Set 2Hz 3 bit timer to 4 (2 sec)
L1517       andm    port2, #$ef             ; Set heart beat sent to diagnostic port
            bra     L1522                   ; Branch to update timer and exit
                                         
            ;----------------------------------------------------
            ; No more long pulse to output 
            ; Check if bit 7 is set (was set when we 
            ; started output of this code)
            ;----------------------------------------------------
L1518       bita    #$80                    ;                             
            beq     L1519                   ; Branch if bit is not set

            ;-----------------------------------------------------------------------------
            ; bit 7 is set, we are therefore at the midpoint between long and short pulse
            ;
            ; reset the flag, set the timer to 1.5 sec, reset output and exit
            ; This is basically a 1.5 sec pause in between long and short pulse
            ;-----------------------------------------------------------------------------
            anda    #$7f                    ; Reset bit 7 (nothing left to output flag). At this point a should be equal to $7f ???
            andb    #$1f                    ; Reset timer to 0 (upper 3 bits)                            
            orab    #$60                    ; Set 2Hz 3 bit timer to 3 (1.5 sec)
            bra     L1521                   ; Branch to reset hearth beat, update timer and exit                               

            ;-----------------------------------------------------------------
            ; Flag was not set, just output whatever short pulses are left...
            ;-----------------------------------------------------------------
L1519       deca                            ; decrement the number of short pulse by 1
            andb    #$1f                    ; reset timer to 0 (upper 3 bits)                       
            orab    #$40                    ; Set 2Hz 3 bit timer to 2 (1 sec)                           
            bra     L1517                   ; Branch to set hearth beat, update timer and exit                             

            ;---------------------------------
            ; A code is currently being output...
            ; At this point we have
            ;       a = errCodeProc   
            ;       b = errCodeIdx  
            ;---------------------------------                 
L1520       cmpb    #$20                    ;                             
            bcs     L1516                   ; Branch if errCodeIdx < $20 (e.g. timer=0, upper 3 bit timer is expired)                            

            ;-------------------------------------                 
            ; Timer not expired check if timer>1
            ;-------------------------------------                 
            cmpb    #$3f                    ;                             
            bhi     L1522                   ; Branch if errCodeIdx > $3f (timer>1)

            ;-------------------------------------------
            ; timer = 1, set heart beat mode output
            ;-------------------------------------------

            ;-------------------------------------------
            ; Reset heart beat output on diagnostic port 
            ;-------------------------------------------
L1521       orm     port2, #$10             ; Reset heart beat sent to diagnostic port 

            ;-------------------------------------------------------------
            ; Decrement errCodeIdx timer (upper 3 bits) by $20 (0.5sec)
            ;-------------------------------------------------------------
L1522       subb    #$20                    ;                             

            ;-----------------------------------------------------
            ; Store new errCodeProc and errCodeIdx and return
            ;-----------------------------------------------------
L1523       staa    errCodeProc             ;                              
            stab    errCodeIdx              ;                              
L1524       rts                             ;                             



;****************************************************************
;
;
; Maf sensor check:
;
;
;****************************************************************
test_maf    ldaa    rpm31                   ;                                                                  
            cmpa    #$10                    ;                                                                 
            bls     L1528                   ;                                                                  
            ldaa    T40_mas                 ; 
            beq     L1526                   ; Branch if timer expired (no mas interrupt for a long time...)
            ldaa    t2_diff8                ;                                                                    
            cmpa    #$31                    ; t2_diff8 more than 49 is an error?                                
            bcs     L1527                   ;                                                                  
L1526       decb                            ;                                                                 
L1527       rts                             ;                                                                 
L1528       incb                            ; return 1 (test not conclusive)                                                                 
            rts                             ;                                                                 



;******************************************************************
;
;
; Crank angle sensor
;
;
;******************************************************************
test_cas    ldaa    T40_engRot              ; 
            bne     L1530                   ; Branch if sensor is fine. T40_engRot is non-zero when CAS interrupts are being received... sensor must be fine...
            brset   port3Snap0, #$40, L1531 ; Branch if key is not in start
            decb                            ; Key is in start but T40_engRot is 0, should not happen -> CAS is bad                            
L1530       rts                             ;                             
L1531       incb                            ; return 1 (test not conclusive)                             
            rts                                                          



;******************************************************************
;
;
; Top dead sensor
;
;
;******************************************************************
test_tdc    ldaa    T40_engRot              ;                                     
            beq     L1535                   ; Branch if timer is 0, (engine not rotating)                             
            ldaa    tdcCheck                ; Engine rotating, check if #1 TDC signal is being received
            beq     L1533                   ; Branch to error if #1 TDC signal is not being received
            ldaa    tdcCasCount             ;                              
            cmpa    #$04                    ;                             
            bcc     L1534                   ; Branch if tdcCasCount>=4                              
            brclr   port3, #$40, L1535      ; tdcCasCount<4, branch if key is in start
L1533       decb                            ; Set error                             
L1534       rts                             ;                             
L1535       incb                            ; return 1 (test not conclusive)                            
            rts                             ;                             



;******************************************************************
;
;
; Reed switch (VSS) sensor check:
;
;
;******************************************************************
test_reed   ldaa    vssCnt1                                                 
            bne     L1537                    ; branch if car is moving (no error since we detected that...)                             
            brset   state1, #$02, L1538      ; Branch if no pulse accumulator interrupts?                                
            brset   port3Snap0, #$80, L1538  ; Branch if Idle switch on (car most likely not moving...)                                   
            ldaa    rpm31                    ;                             
            cmpa    #$60                     ;                            
            bls     L1538                    ;                             
            ldaa    airVol                   ;                              
            cmpa    #$6d                     ;                            
            bls     L1538                    ;                             
            brset   state3, #$04, L1538      ; Branch if rev limiter active
            ldaa    T2_stCrank               ;                                  
            adda    #$78                     ;                            
            bcs     L1538                    ;                             
            decb                             ;                            
L1537       rts                              ;                            
L1538       incb                             ; return 1 (test not conclusive)                             
            rts                              ;                            



;******************************************************************
;
;
; Injector circuit check
;
;
;******************************************************************
test_inj    ldaa    obdInjCmd               ; First check if we disabled an injector on purpose (OBD command)                             
            coma                            ;                             
            bita    #$3f                    ; only keep 6 bits (6 inj.)                             
            bne     L1541                   ; Branch if disabled on purpose                              
            ldaa    T40_engRot              ;                               
            beq     L1541                   ; Branch if engine not rotating                              
            ldaa    rpm31                   ;                              
            cmpa    #$20                    ;                             
            bcc     L1541                   ; Branch if rpm > 1000                             
            ldaa    tpsRaw                  ;                            
            cmpa    #$24                    ;                             
            bcc     L1541                   ; Branch if tpsRaw > $24                             
            brclr   injBad, #$01, L1540     ; Branch if injector OK?
            decb                            ; Error, set flag                            
L1540       rts                             ;                             
L1541       incb                            ; return 1 (test not conclusive)                             
            rts                                                          



;******************************************************************
;
;
; Fuel pump relay check
;
;
;******************************************************************
test_fpump  brclr   port3Snap0, #$40, L1543     ; Branch if key in start position                               
            brset   port1, #$10, L1545          ; Branch if fuel pump relay bit set 
L1543       brclr   port4Snap, #$40, L1544      ; Fuel pump driven feedback???                                
            decb                                                         
L1544       rts                                                          
L1545       incb                                ; return 1 (test not conclusive)                         
            rts                                                          



;******************************************************************
;
;
; Ignition coil check:
;
;
;******************************************************************
test_coil   brset   state1, #$11, L1548       ; Branch if notRotating or startingToCrank
            ldaa    rpm31                     ;                              
            cmpa    #$a0                      ;                             
            bcc     L1548                     ; Branch if RPM >= 5000                              
            brclr   coilChkFlags, #$80, L1547 ; Branch if no error found on ignition signal
            decb                              ; Error was found                             
L1547       rts                               ;                             
L1548       incb                              ; return 1 (test not conclusive)                             
            rts                                                          



;******************************************************************
;
;
; Knock sensor check:
;
;
;******************************************************************
test_knock  brset   port4Snap, #$20, L1550  ; Knock sensor related???
            decb                                                         
L1550       rts                                                          



;******************************************************************
;
;
; Intake air temperature sensor check:
;
;
;******************************************************************
test_iat    brclr   state2, #$02, L1552                                     
            decb                                                         
L1552       rts                                                          



;******************************************************************
;
;
; Tps sensor check:
;
;
;******************************************************************
test_tps    ldaa    tpsRaw                                                 
            cmpa    #$66                                                 
            bhi     L1554                   ; branch if tpsRaw voltage higher 40%                                   
            cmpa    #$0a                    ;                                                                       
            bcs     L1555                   ; branch if voltage lower than 4%                                      
            rts                             ;                                                                       
L1554       brclr   port3Snap0, #$80, L1556 ; branch if idle switch is off                                            
L1555       decb                            ;                                                                       
L1556       rts                             ;                                                                       



;******************************************************************
;
;
; Ect sensor check:
;
;
;******************************************************************
test_ect    brset   state2, #$10, L1563     ; Branch if flag was previously set when we were here (once in error always in error????)                                
            brclr   state2, #$01, L1558     ; Branch if no ect error flag set in main code
            ldaa    T2_stCrank              ; ect error flag is set in main code, check timer                             
            adda    #$78                    ;                             
            bcc     L1562                   ; Branch if more than 60sec have elapsed since engine startedToCrank (should have cleared by now?, sensor is in error)                              
L1558       brset   state1, #$10, L1560     ; Branch if notRotating (not conclusive)
            ldaa    T0p5_ect                ;                               
            beq     L1563                   ; Branch if temperature stayed at exactly 88degC for more than 5 minutes (????)
            ldaa    T0p5_crank2             ;                               
            adda    #$5a                    ;                             
            bcs     L1559                   ; Branch if less than 180s have elapsed since ectStCrank was loaded                              

            ;----------------------------------------------------------
            ; More than 180s have elapsed since ectStCrank was loaded
            ;----------------------------------------------------------
            ldaa    ectStCrank              ;                                   
            cmpa    #$ff                    ; Not sure how we would get that value, maybe if sensor is broken??                            
            bcs     L1559                   ; Branch if ectStCrank < $ff (branch almost always???????)                              
            suba    #$0a                    ; a=ectStCrank-$0a = $ff-$0a = $f5, am I missing someting??????????????                             
            cmpa    ectFiltered             ;                                     
            bcs     L1562                   ; Branch if  ectFiltered > $f5 ?????? (sensor error)                             
L1559       ldaa    ectFiltered             ;                                    
            cmpa    #$54                    ; 41degC                             
            bcs     L1561                   ; Branch if temperature(ectFiltered) > 41degC (no error)                               
L1560       incb                            ; return 1 (test not conclusive)                             
L1561       rts                                                          
L1562       ldaa    T2_snsrChk                                                 
            bne     L1563                                                 
            orm     state2, #$10                                             
L1563       decb                                                         
            rts                                                          



;******************************************************************
;
;
; Barometer sensor check
;
;
;******************************************************************
test_baro   ldaa    T40_baro                ;                                  
            bne     L1567                   ;                              
            ldaa    baroRaw                 ;                                
            cmpa    #$e6                    ;                             
            bhi     L1565                   ;                              
            cmpa    #$0a                    ;                             
            bcc     L1566                   ;                              
L1565       decb                            ;                             
L1566       rts                             ;                             
L1567       incb                            ; return 1 (test not conclusive)                             
            rts                                                          



;******************************************************************
;
;
; Serial port interrupt subroutine 
;
;
;******************************************************************
serialRxInt ldd     sci_scr                 ; A=sci_cr, B=sci_read                                                                                       
            bita    #$80                    ; Check if something was received??/start of sequence to clear flag                                      
            beq     L1570                   ;                                                                                                            
            brset   obdFlags, #$80, L1569   ; Branch if the code we received is the echo of the one we just sent                                          
            stab    obdCode                 ;                                                                                                            
            orm     obdFlags, #$40          ; Indicate new value available                                                                                 
            bra     L1570                   ;                                                                                                            
L1569       andm    obdFlags, #$7f          ; The code we received is the echo of what we sent, just drop it and reset flag                                
L1570       rti                             ;                                                                                                           



;******************************************************************
;
;
;
;
;
;******************************************************************
loadConfig  ldx     #t_strap1               ;                                  
            ldab    port4                   ;                              
            nop                             ;                             
            andb    #$03                    ; Keep only config resistor bits                             
            aslb                            ;                             
            abx                             ;                             
            ldd     $00,x                   ;                              
            std     config1                 ;                              
            rts                             ;                             



;******************************************************************
;
;
; Initialize a few things
;
;
;******************************************************************
initFunc1   ldd     #$7e16                  ;                                                                                                  
            std     p1_ddr                  ; Initialize port1 and port2 data direction registers                                              
            ldd     #$0000                  ;                                                                                                  
            std     p3_ddr                  ; Initialize port3 and port4 data direction register (all inputs)                                  
            ldaa    #$fe                    ;                                                                                                
            staa    p5_ddr                  ; Initialize port5 data direction register
            clra                            ;                             
            staa    L000f                   ;                              
            staa    L0017                   ;                              
            andm    port1, #$bf             ; Reset ??????                               
            ldaa    #$00                    ;                             
            staa    L0024                   ;                              

            ;-------------------------------------------------------
            ; rti_freq is setting the real time interrupt frequency:
            ;    F=125000/(256-x)
            ;       x      F
            ;      0x64  1*801.28Hz
            ;      0xb2  2*801.28Hz
            ;      0xcc  3*801.28Hz
            ;      0xd9  4*801.28Hz
            ;-------------------------------------------------------
            ldd     #$4d64                  ; 
            std     rti_ctl                                                 
            rts                                                          



;******************************************************************
;
; Input: D = Tcas (period of cas interrupts in sec * 125000)
; Output: freq = $EA600/D = 960000/D
;
;        in the end, rpm = freq/8*31.25 
;
;        e.g. 1000RPM -> Tcas = 60/1000* 125000/2 = 3750
;                        freq = 960000/3750 = 256
;                        rpm = freq/8*31.25 = 1000 RPM 
;
;******************************************************************
calcFreq    std     temp4                   ;                                                                 
            ldd     #$a600                  ;                                                                  
            std     temp2                   ;                                     
            ldd     #$000e                  ; numerator = D:temp2 = 000EA600                                   
            bra     div3216                 ; D = (#$000EA600)/([$5A $5B])      


                                                           
;******************************************************************
;
;
;
;
;******************************************************************
mul816_baro ldab    baroFact                                                 

;******************************************************************
;
;
;
;
;******************************************************************
mul816_256  jsr     mul816_128              ; D and [temp6:temp7] = b*[temp6:temp7]/128                                   
            jmp     scale2m                                                 



;******************************************************************
;
; Input 
;     x = point to table1
;     y = point to table2
;
; Output
;     d = injMasComp * table1(rpm)/128 * table2(ect)/16 * baroFact/128
;
;******************************************************************
L1577       ldd     injMasComp              ; d = injMasComp                                   
            std     temp6                   ; temp6:temp7 = injMasComp                             
            jsr     interp16rpm             ; b = table1(rpm)                              
            jsr     mul816_128              ; [temp6:temp7] = injMasComp * table1(rpm)/128                                   
            xgxy                            ; x points to table2                              
            jsr     interpEct               ; b = table2(ect)                                  
            ldaa    baroFact                ; a = baroFact                                
            mul                             ; d =  table2(ect) * baroFact                           
            jmp     mul1616_2K              ; d = 8* injMasComp * table1(rpm)/128 * table2(ect)/128 * baroFact/128



;******************************************************************
;
; 8 bit by 16 bit multiplication
;
; Input
;   b: 8 bit value
;   [temp6:temp7]: 16 bit value, optionally in X if called from mul816b
;
; Output: 
;   D and [temp1:temp2] = b*[temp6:temp7]/256
;   temp3 = Lo(b*temp7) (fractional part of result) 
;
;
;
;******************************************************************
mul816      ldx     temp6                   ;                              
mul816b     stx     temp1                   ; temp1,temp2 = temp6,temp7                              
            pshb                            ; save b                            
            ldaa    temp2                   ; a = temp7                             
            mul                             ; d = b*temp7                            
            std     temp2                   ; temp2, temp3 = b*temp7                             
            ldaa    temp1                   ; a=temp6                             
            pulb                            ;                             
            mul                             ; d = b*temp6                              
            addb    temp2                   ; d = b*temp6 + b*temp7/256 = b*(temp6+temp7/256) = b*[temp6:temp7]/256
            adca    #$00                    ; Propagate addition carry                            
            std     temp1                   ; temp1, temp2 = b*[temp6:temp7]/256
            rts                             ;                             



;******************************************************************
;
;
; 16 bit by 16 bit multiplication:
;
; Input:
;               a:b = 16 bit value  (val1:val2)
;       temp6:temp7 = 16 bit value1 (val3:val4)
;
; Output:
;               d = [a:b]*[temp6:temp7]/65536  (or equivalently, 16 upper bits of result)
;           temp2 = lower 8 bits (of 24) of results
;----------------------------------------
;
; D * temp6:temp7
; - 16 bit multiplication:
; - D * temp6:temp7 , High bytes stored in D
; -
; - (1) * (2) is equal to ( 1A + 1B ) * ( 2A + 2B )
; 
; - = 1A * 2A + 1A * 2B + 1B * 2A + 1B * 2B
; 
; - Where:
; - lets call temp6:temp7 Argument (1)
; - lets call reg D Argument (2)
; -
; - temp6 is then named (1A)
; - temp7 is then named (1B)
; - and temp6:temp7 = (1A) * #$100 + (1B)
; -
; - Reg D is reg A:reg B
; - A is then named (2A)
; - B is then named (2B)
; - temp6:temp7 = (1A) * #$100 + (1B)
; 
; - D consists of (2A) * #$100 + (2B)
; 
; -Result (R) will be 32 bit, (R3)-(R0) where
; -temp3 = (R0) low
; -temp2 = (R1)
; -temp1 = (R2) --\ Stored and returned in D
;
;******************************************************************
mul1616     ldx     #temp6                  ; x points to temp6
            psha                            ; st0 = val1                            
            pshb                            ; st1 = val2                            
            ldaa    $01,x                   ; a = val4                             
            mul                             ; d = val4*val2                            
            std     temp2                   ; temp2:temp3=val4*val2                             
            pulb                            ; b = val2                            
            ldaa    $00,x                   ; a = val3                             
            mul                             ; d = val2*val3                            
            addb    temp2                   ; d = val2*val3 + val4*val2/256
            adca    #$00                    ; propagate carry                            
            std     temp1                   ; temp1:temp2 = val2*val3 + val4*val2/256
            pula                            ; a = val1                            
            psha                            ; st0 = val1                            
            ldab    $01,x                   ; b = val4                             
            mul                             ; d = val1*val4                            
            addd    temp1                   ; d = val1*val4 + val2*val3 + val4*val2/256
            std     temp1                   ; temp1:temp2 = val1*val4 + val2*val3 + val4*val2/256
            pula                            ; a = val1                            
            rorb                            ; shift in carry bit                            
            andb    #$80                    ; keep only carry bit                             
            pshb                            ; st0 = carry bit in position $80                            
            ldab    $00,x                   ; b=val3                             
            mul                             ; d=val1*val3                            
            xgdx                            ; x=val1*val3, d points to temp6
            pulb                            ; b=carry bit in position $80                            
            abx                             ; add 2 x carry bit (since shifted right previously)                            
            abx                             ; x=val1*val3 + carry                               
            ldab    temp1                   ; b = (val1*val4 + val2*val3 + val4*val2/256)/256
            abx                             ; x = val1*val3 + carry + (val1*val4 + val2*val3 + val4*val2/256)/256
            xgdx                            ; x points to temp6, d = val1*val3 + carry + (val1*val4 + val2*val3 + val4*val2/256)/256
            rts                             ;                             
                                            


;******************************************************************
;
;
; fractional 32 bit by 16 bit division:
; input: D:temp2:temp3 = 32 bit numerator; 
;        temp4:temp5 = 16 bit denominator
;
; output: D = quotient
;         X = remainder
;
;******************************************************************
div3216     cmpd1   temp4                   ;                                                                                    
            bcs     L1582                   ; Branch if denominator > numerator (results<1)                                      
            ldd     #$ffff                  ; denominator<=numerator, return .99998....                                           
            bra     L1586                   ;                                                                                    
                                                                                                   
L1582       ldy     #$0010                  ; Loop 16 times                                                                       
            ldx     temp2                                                 
L1583       xgdx                                                         
            asld                                                         
            xgdx                                                         
            rolb                                                         
            rola                                                         
            bcs     L1584                                                 
            cmpd1   temp4                                                 
            bcs     L1585                                                 
L1584       subd    temp4                                                 
            inx                                                          
L1585       decy                                                         
            bne     L1583                                                 
            xgdx                                                         
L1586       rts                                                          
            


;******************************************************************
;
;
; 2D table lookup/interpolation
;
; Input:
;       temp6 = in1 (column index*16) (optionally in a if using 2Dlookup2)
;       temp7 = in2 (row index*16)    (optionally in b if using 2Dlookup2)
;       hi(Y) = scale, number of elements per row in the table 
;       lo(Y) = offset, added to value loaded from table before interpolation
;           X = 2Dtable address
;
; Output: A and B contain the same 2D interpolated value from the table 
;         
;
;
;******************************************************************
lookup2D    ldd     temp6                   ; a=in1, b=in2                              
lookup2D2   sty     temp3                   ; temp3 = scale temp4=offset                              
            staa    temp5                   ; temp5 = in1                              
            clra                            ; a=0, b=in2
            asld                            ;                             
            asld                            ;                             
            asld                            ;                             
            asld                            ; d = in2*16                             
            pshb                            ; st0 = LO(in2*16)                            
            ldab    temp3                   ; b=scale                             
            mul                             ; d = in2*16/256*scale                             
            stx     temp1                   ; temp1:temp2 = 2Dtable
            addd    temp1                   ; d = 2Dtable + in2*16/256*scale
            std     temp1                   ; temp1:temp2 = 2Dtable + in2*16/256*scale
            ldx     temp1                   ; X =  2Dtable + in2*16/256*scale, first row of interpolation
            pshx                            ; st1:st2 = 2Dtable + in2*16/256*scale
            ldab    temp3                   ; b=scale                              
            abx                             ; X = 2Dtable + in2*16/256*scale + scale, go to next row of interpolation...
            bsr     L1589                   ; Calculate interpolated value on second row, result in b                              
            stab    temp3                   ; temp3 = interpolated value on second row                             
            pulx                            ; x = 2Dtable + in2*16/256*scale (first row)
            bsr     L1589                   ; Calculate interpolated value on first row, result in b                               
            stab    temp2                   ; temp3 = interpolated value on first row                               
            pula                            ; a = LO(in2*16)                              
            ldx     #temp2                  ;                                
            bra     interpSpec              ; Interpolate temp variables temp2 and temp3 using fractional part a=LO(in2*16) with no scaling on a and return to calling sub, result in b



;******************************************************************
;
;
; Used by lookup2D, interpolate on one row between two columns
;
;
;******************************************************************
L1589       ldaa    temp5                   ; a = in1                              
            clrb                            ; b=0                             
            lsrd                            ;                             
            lsrd                            ;                             
            lsrd                            ;                             
            lsrd                            ; d = in1*256/16 = in1*16                             
            pshb                            ; st3 = LO(in1*16)
            tab                             ; b=in1*16/256=in1/16
            pula                            ; a=LO(in1*16)
            abx                             ; X = startOfRow + in1/16
            ldab    $00,x                   ; b = val1, table lookup, get value in row                             
            addb    temp4                   ; b = val1 + offset                             
            stab    temp1                   ; temp1 = val1 + offset                             
            ldab    $01,x                   ; b = val2, next value in table on same row                             
            addb    temp4                   ; b = val2 + offset                            
            stab    temp2                   ; temp2 = val2 + offset                             
            ldx     #temp1                  ; X points to temp variables
            bra     interpSpec              ; Interpolate temp variables temp1 and temp2 using fractional part a=LO(in1*16) with no scaling on a and return to calling sub, result in b



;******************************************************************
;
; Interpolate a table using ectCond, (ectCond is inv. proportional to temp)
; This one compensate for non constant distance between the table points
;
; Used in the calculation of injPwStart
; Input X = table
;
;
;
;******************************************************************
interpEct2  ldab    ectCond                 ; b = ectCond (ect conditionned for table interp..)                            
            cmpb    #$c0                    ; -7degC                            
            bcs     L1591                   ; Branch if ectCond < $c0
            clra                            ; a = 0, d = ectCond 
            asld                            ; d = 2*ectCond                            
            subd    #$00c0                  ; d = 2*ectCond -$c0                              
            jsr     ovfCheck                ;                              
L1591       tba                             ; a = 2*ectCond -$c0                              
            bra     interp32                ;                                 



;******************************************************************
;
;
; Interpolate a table using ECT (ectCond is inv. proportional to temp)
; Input X = table
;
;
;******************************************************************
interpEct   ldaa    ectCond                                                 
            bra     interp32                                                 



;******************************************************************
;
;
;
;
;
;******************************************************************
interp16rpm ldaa    rpmIndex1                                                 
            bra     interp16b                                                 



;******************************************************************
;
;
; Interpolate table using Conditionned IAT (iatCond)
;
;
;******************************************************************
iatCInterp  ldaa    iatCond                                                 
            bra     interp32                                                 



;******************************************************************
;
;
;
;
;
;******************************************************************
interp16b   clrb                                                         
            bra     interp16                                                 



;******************************************************************
;
; Table lookup with fractional interpolation
; input value = A
; input table = X
; output value in a and b is (interpolated table) = X(A/32)
;
;
;******************************************************************
interp32    clrb                            ;                             
            lsrd                            ; 
interp16    lsrd                            ;                             
            lsrd                            ;                             
            lsrd                            ;                             
            lsrd                            ; A=A/32, B = 5 LSB of A in upper part 
interp1     pshb                            ; \                                                                                                
            tab                             ;  >transfer A to B, only 3 bits left                                                              
            pula                            ; / At this point, B=integer part of input/32, A=fractional part                                   
            abx                             ; ADD B TO X:  B = 0 to 7 (3 bits) (integer table lookup), X=V(0)     
                                                                                                                                           
interpSpec  tsta                            ; 
            beq     L1601                   ; Branch if a = 0 (no fractional interp)                                                       
            ldab    $01,x                   ; B=V(1)                                                                                            
            subb    $00,x                   ; B=V(1)-V(0)                                                                                       
            bcc     L1600                   ; banch if V(1)-V(0) > 0                                                                             
            inx                             ; negative->X=V(1)                                                                                 
            negb                            ;                                                                                                  
            nega                            ;                                                                                                  
L1600       mul                             ; D=A*B (                                                                                          
            aslb                            ; shift left B (... carry)                                                                         
L1601       adca    $00,x                   ; add to a with carry                                                                               
            tab                                                          
            rts                                                          



;******************************************************************
;
; Interpolate table an multiply result by [temp6:temp7]
; 
;
;
;******************************************************************
interp32mul   bsr     interp32                                                 
            ; continued below...



;******************************************************************
;
;  Multiply 8 bit by 16 bits, final result is scaled by 128, 
;  rounded and checked for overflow
;
; input:
;   b: 8 bit value
;   [temp6:temp7]: 16 bit value
;
; output:      
;   D and [temp6:temp7]: rounded 2*b*[temp6:temp7]/256 = b*[temp6:temp7]/128
;
;
;******************************************************************
mul816_128  jsr     mul816                  ; D = b*[temp6:temp7]/256                              
            asl     temp3                   ; Get lowest bit from fractional part                              
            rolb                            ; Shift it in                            
            rola                            ; shift it in, D = 2*b*[temp6:temp7]/256 
            bcs     L1604                   ; Branch if overflow                             
            asl     temp3                   ; No overflow, Get second lowest bit from fractional part
            adcb    #$00                    ; Add it to result (round-up result)                            
            adca    #$00                    ; propagate                            
            bcc     L1605                   ; Branch if no overflow                             
L1604       ldaa    #$ff                    ; Overflow, return max value                            
L1605       std     temp6                   ; Store result                             
            rts                             ;                             
                                            


;******************************************************************
;
; Input:
;               D = 16 bit value1 (should be only 11 or 12 bits???)
;     temp6:temp7 = 16 bit value2
;
; Output:
;       D and [temp6:temp7] = rounded value1*value2/128 (a=$ff in case of overflow)
;       Optionally, divided by and additional 4 if mul1616_512 is used or 16 if mul1616_2K is used
;
;******************************************************************
mul1616_128 asld                            ;                              
            asld                            ;                             
mul1616_512 asld                            ;                             
            asld                            ; D = value1 * 16                            
mul1616_2K  jsr     mul1616                 ; D = (value1 * 16 * value2)/65536 (upper 16 bits of mul1616)                              
            ldx     temp2                   ; X = lower 16 bits of (value1 * 16 * value2)                             
            xgdx                            ; D = lower 16 bits of (value1 * 16 * value2), X = (value1 * 16 * value2)/65536                           
            ldab    #$03                    ; a = 3rd part of mul1616, b=3=number of loop to execute                            

            ;--------------------------------------------
            ; Loop 3 times to divide 24 bit result by 8 
            ;--------------------------------------------
L1609       xgdx                            ; Xhi = 3rd part of mul1616, Xlo = 3, D = (value1 * 16 * value2)/65536
            lsrd                            ; D = (value1 * 16 * value2)/65536/2^n, carry = lower bit
            xgdx                            ; X = (value1 * 16 * value2)/65536/2^n, a = 3rd part of mul1616/2^(n-1), b=3 on first loop                             
            rora                            ; shift in carry, a = (3rd part of mul1616)/2^n, b=3 on first loop
            decb                            ; b=b-1                           
            bne     L1609                   ; loop

            ;------------------------------------------------------------
            ; Round-up and check for overflow in A
            ; At this point, 24 bit result should have been
            ; shifted down to fit only in 16 bits, upper 8 bit
            ; should be 0, if not, b will be loaded with $ff in scale1m
            ;------------------------------------------------------------
            adca    #$00                    ; Round-up result 3rd part of result                            
            psha                            ; st0 = lower 8 bit of result                            
            xgdx                            ; D = (value1 * 16 * value2)/65536/8                             
            bsr     scale1m                 ; Propagate carry from 3rd part of result to D and check for overflow 

            ;-----------------------------------------------------------------------
            ; At this point, we assume upper 8 bits=0 and only keep lower 16 bits
            ;-----------------------------------------------------------------------
            tba                             ; a =  2nd part of 24 bit result                            
            pulb                            ; b =  lower 8 bit of 24 bit result, in short, D=(value1 * 16 * value2)/256/8 = value1*value2/128
            std     temp6                   ; temp6:temp7 = value1*value2/128
            rts                             ;                             
            


;******************************************************************
;
; Scaling function with rounding
; Divide d by 128 or 64, etc.
;
;
;
;******************************************************************
scale128    lsrd                              ;                           
scale64     lsrd                              ;                           
            lsrd                              ;                           
scale16     lsrd                              ;                           
scale8      lsrd                              ;                           
            lsrd                              ;                           
            lsrd                              ;                           
            adcb    #$00                      ; Round-up by adding carry bit                          
            adca    #$00                      ; propagate addition                          
            rts                               ;                            
                                             


;******************************************************************
;
; Input:
;       d = v1:v0
;
; Output:
;       a = v1 rounded up depending on v0, up to max of $ff
;
;
;******************************************************************
round256    aslb                            ; Shift high bit of b in carry
            adca    #$00                    ; roundup a                            
            bcc     L1615                   ; branch if no overflow                             
            deca                            ; Overflow, use max of $ff                            
L1615       rts                             ;                             



;******************************************************************
;
;
; Divide D by 128 or 64 or 32... in order for the value to fit
; only in b (with a=0). If it does not fit (a<>0), b is loaded with 
; max value of $ff
;
;
;
;******************************************************************
scale128m   lsrd                                                         
scale64m    lsrd                                                         
            lsrd                                                         
scale16m    lsrd                                                         
scale8m     lsrd                                                         
scale4m     lsrd                                                         
scale2m     lsrd                            ; D = D/128, carry contains last bit shifted out                                        
scale1m     adcb    #$00                    ; Add last bit shifted out (round-up number)                                            
            adca    #$00                    ; propagate addition of last bit                                                        
ovfCheck    tsta                                                         
            beq     L1624                   ; branch if A=0                                                                                            
            ldab    #$ff                    ; A is not 0, set fractional part to FF (the only one returned...)                              
L1624       rts                                                          



;******************************************************************
;
;
; Apply an offset and clip input, the result is usually used to 
; interpolate a table with a value of known range...
;
;        in Xhi = max value
;        in Xlo = offset
;        in   b = input value
;
;        out b = max(min(b,Xhi)-Xlo,0)
;
;
;******************************************************************
clipOffset  stx     temp1                                                 
            cmpb    temp1                                                 
            bcs     L1626                                                 
            ldab    temp1                                                 
L1626       subb    temp2                                                 
            bcc     L1627                                                 
            clrb                                                         
L1627       rts                                                          



;******************************************************************
;
; This function is used to apply a piecewise linear transformation
; to the input value, see L2052, L2053 and L2054. This can be seen
; as calculating the index into a table where the spacing between
; table entries is not constant (first three entries spaced by x,
; next three spaced by 2x, etc...)
;
; Input:
;       a = val
;       b = 0 (ignored or cleared)
;       y = points to table with first two values being a max 
;           and offset and the rest being triplets (addVal, nshift, compVal)
;           where compVal is monotonicaly increasing... 
;
; Output:
;       a = (min(val,max) - offset + addVal)/2^(nshift-1)
;       
;       where max and offset are the first two values of the table
;       and where addVal and nShift are taken from the table according to val-offset
;
;******************************************************************
            ;------------------------------------------------------
            ; Apply max value of table, a = min(val,table[0])
            ;------------------------------------------------------
pwiseLin    cmpa    $00,y                   ; Operation does ++y...I assume                             
            bcs     L1629                   ; Branch if a < table[0]                             
            decy                            ; --y, go back to 0                           
            ldaa    $00,y                   ; a=table[y++]                             
            clrb                            ; b=0
                  
            ;----------------------------------------------------------                      
            ; Subtract offset of table, a = val-table[1] = val-offset
            ;----------------------------------------------------------                      
L1629       suba    $00,y                   ; a = val-table[y++] = val-offset                             
            bcc     L1630                   ; Branch if result positive                             
            clra                            ; Result negative, d=0                            
            clrb                            ; d=0
                                        
            ;----------------------------------------------
            ; Loop until we find compVal > a 
            ;----------------------------------------------
L1630       ldx     $00,y                   ; x = table[y]:table[y+1]; y = y + 2                               
            cmpa    $00,y                   ; Operation does ++y...I assume                             
            bcc     L1630                   ; Loop if  a >= table[y]                              

            ;-------------------------------------------------------------- 
            ; Store the corresponding addVal and nshift in temp1 and temp2
            ;-------------------------------------------------------------- 
            stx     temp1                   ; temp1 = addVal;, temp2 = nshift

            ;--------------------------------------------
            ; Add addVal to a, a = val - offset + addVal
            ;--------------------------------------------
            adda    temp1                   ; a = a-offset+addVal 
            
            ;----------------------------------------------------------------
            ; Apply nshift to a, a =  (val - offset + addVal)/2^(nshift-1)
            ;----------------------------------------------------------------
L1631       dec     temp2                   ; temp2=table[y+1]-1
            beq     L1632                   ; Btanch if table[y+1]-1 =0
            lsrd                            ; d = d/2                            
            bra     L1631                   ; Loop                             
L1632       rts                             ;                             



;******************************************************************
;
; Input: 
;       y: point to piecewise linear transformation table
;
; Apply piecewise linear transformation to rpm4 and scale
;
;
;******************************************************************
rpmPwise    ldd     rpm4                    ;                              
            asld                            ;                             
            asld                            ; d = rpm4*4                            
            bsr     pwiseLin                ;                              
            bra     scale16m                ;                                 



;******************************************************************
;
;
; Decrement value at X by 1 (min of 0) if Tclocks.0 (40Hz signal) is set
;
;
;******************************************************************
decX40Hz    ldab    #$01                                                 
            brclr   Tclocks, #$01, L1637                                     



;******************************************************************
;
;
; Decrement all values in a given table by 1, stop at min value 0
; X points to table, b is number of elements
;
;
;******************************************************************
decTable    brclr   $0000,x,#$ff,L1636  
            dec     $0000,x                                                 
L1636       inx                                                          
            decb                                                         
            bne     decTable                                                 
L1637       rts                                                          



;******************************************************************
;
; Lookup the given table using config2 
; lowest 2 bits as index to 16 bits values
;
; Input:
;     x: points to table
;
; Output:
;
;     x(16 bits): table(2*(config2 & $03))
;
;******************************************************************
cfgLookup16 ldab    config2                 ; b = config2                               
            andb    #$03                    ;                             
            aslb                            ; b = 2*(config2 & $03)                            
            abx                             ; x points to table(2*(config2 & $03))                            
            ldx     $00,x                   ; x =  table(2*(config2 & $03))                             
            rts                             ;                             



;******************************************************************
;
; Read value from IO port (ADC) using a and b (d) as the values
; to write to adc_ctl and adc_data respectively. a should be set
; to the port number (0 to 7 as indicated below) with the start bit
; set to 1 ($08) 
;
;     Port $00: ECT (engine coolant temp)
;     Port $01: IAT
;     Port $02: BARO
;     Port $03: O2
;     Port $04: EGRT
;     Port $05: BATT
;     Port $06: KNOCK count
;     Port $07: TPS
;
;
;******************************************************************
readAdc1    sei                            ; set interrupt mask             
readAdc2    std     adc_ctl                ; set port #                     
            brn     L1641                  ; time delay                     
L1641       div     airCntDef              ; time delay                     
            mul                            ; time delay                     
            mul                            ; time delay                     
            mul                            ; time delay                     
            mul                            ; time delay                     
            mul                            ; time delay                     
            mul                            ; time delay                     
            mul                            ; time delay                     
            ldd     adc_ctl                ; get port value                 
            rts                                                          



;******************************************************************
;
;
; input: rpm in b, maxRpm in a 
;        (note that airVol is also used instead of rpm in 
;         calling this function)
;
; output:   b = min(max(rpm-$10,0), maxRpm)      $10->500rpm
;
;******************************************************************
rpmRange    subb    #$10                    ;                                              
            bcc     abmin                   ; Branch if result positive
            clrb                            ; Use min of 0

            ;--------------------------------------------
            ; Code below also called as a function
            ; abmin -> b = minimum of a and b (can also 
            ; be seen as applying a max...)
            ;--------------------------------------------
abmin       cba                             ; compare (A-B)                                
            bcc     L1644                   ; Branch if b<=maxRpm
            tab                             ; b = maxRpm
L1644       rts                             ; return                                  



;******************************************************************
;
; Input:
;     None (a=airVol if called from L1647)
;
; Output: in b (same result in a):
; 
;     airVol[T]B  < 60: airVol[T]B - $20
;     airVol[T]B >= 60: 0.668 * airVol[T]B
;
; The maximum of airVolTB or airVolB is used, see comments below
;
;----------------------------------------
;
; the ecu makes a temp value for the table lookup..
; so if 0xe3 <= 96, value = 0xe3 - 32,
; if 0xe3 > 96, value = 0xe3 * 2/3
;
;******************************************************************
getLoadForMaps
#ifdef extLoadRange
#ifdef extLoadRange2
            ldaa    L0054                   ; a = airVol16/4
            ldab    baroFact                ; b = baroFact
            mul                             ; d = airVol16/4 * baroFact
            jsr     scale128m               ; b = airVol16/4 * baroFact/128
            ldaa    iatCompFact             ; a = iatCompFact 
            bpl     test123                 ; Branch if iatCompFact < $80
            mul                             ; d = airVol16/4 * baroFact/128  * iatCompFact
            jsr     scale128m               ; b = airVol16/4 * baroFact/128  * iatCompFact/128
test123     tba                             ; a = airVol16/4 * baroFact/128 [* iatCompFact/128]
#else
            ldaa    L0054                   ; a = airVol16/4
            bra     L1647
            nop
            nop
            nop
            nop
            nop
            nop
            nop
#endif
#else
            ;-----------------------------------------------------
            ; Decide on which value to use, airVolTB or airVolB
            ;
            ; Done this way, it correspond to taking the 
            ; highest of the two since:
            ;
            ;       airVolTB = airVolB * iatCompFact/128
            ;
            ;       if iatCompFact<128  -> max is airVolB 
            ;       if iatCompFact>=128 -> max is airVolTB 
            ;
            ; Since the load is used to interpolate the fuel map,
            ; it is probably safer to use the maximum of the two 
            ; value, i.e. assume there is more air than less and 
            ; therefore risk of running too rich. The risk of using 
            ; only airVolTB is that if the temperature sensor is 
            ; heat soaked then it will report a higher temperature 
            ; than the actual temperature of the air getting in.
            ; This means that airVolTB will report less air than
            ; is actually getting in and there won't be enough 
            ; fuel injected -> we will run too lean... 
            ;-----------------------------------------------------
            ldaa    iatCompFact             ; a=iatCompFact ($80=100%)                                   
            bpl     L1646                   ; Branch if iatCompFact<100%                              
            ldaa    airVolTB                ; iatCompFact>=100%, a = airVolTB                                 
            bra     L1647                   ;                              
L1646       ldaa    airVolB                 ; iatCompFact<100%, a = airVolB                               
#endif

            ;-------------------------------------
            ; Compute load index from air volume
            ;-------------------------------------
L1647       tab                             ; a = b = airVol[T]B
            subb    #$60                    ; b = airVol[T]B - $60
            bcs     L1648                   ; branch if underflow (airVol[T]B <$60)
            ldaa    #$ab                    ; a = $ab                            
            mul                             ; d = $ab * (airVol[T]B - $60)
            aslb                            ; Shift higher bit of b in carry
            adca    #$00                    ; Round-up a                            
            adda    #$60                    ; a = rounded $ab * (airVol[T]B - $60)/256 + $60
L1648       suba    #$20                    ; a = a-20                             
            bcc     L1649                   ; branch if no overflow                             
            clra                            ; use min value                            
L1649       tab                             ; a = b = result                            
            rts                             ;                             



;******************************************************************
;
; Input: temp22:temp23 = v1:v0 (set to Tcas)
;
; Output 
;       d = abs([temp22:temp23] - TcasLast0) - [temp22:temp23] * $30//256
;
;******************************************************************
L1650       ldaa    temp22                  ; a = v1
            ldab    #$30                    ; b = $30                             
            mul                             ; d = $30 * v1                             
            xgdx                            ; x = $30 * v1                            
            ldaa    temp23                  ; a = v0                             
            ldab    #$30                    ; b = $30                            
            mul                             ; d = $30 * v0                            
            tab                             ; b = $30 * v0 /256                            
            abx                             ; x = $30 * v1 + $30 * v0 /256 = $30*(v1+v0/256) = [temp22:temp23] * $30//256                           
            stx     temp20                  ; temp20 = [temp22:temp23] * $30//256                           

            ;---------------------------------------
            ; Compute abs(temp22:temp23 - TcasLast0)
            ;---------------------------------------
            ldd     temp22                  ; d = temp22:temp23                             
            subd    TcasLast0                ; d = temp22:temp23 - TcasLast0                              
            bcc     L1651                   ; Branch if result positive
            coma                            ; Result negative, make it positive                            
            comb                            ;                             
            addd    #$0001                  ; two's complement...                              

            ;----------------
            ; Compute result
            ;----------------
L1651       subd    temp20                  ; d = abs(temp22:temp23 - TcasLast0) - [temp22:temp23] * $30//256                                    
            rts                             ;                             



;******************************************************************
;
;
; Input capture interrupt 1
;
; Main CAS interrupt routine, triggered on both the rising
; and falling edge of the CAS signal (edge detection polarity 
; is toggled in the code upon each interrupt)
;
;
;******************************************************************
            ;------------------------------------------------
            ; Read t3_clock1 for later use and then 
            ; read t1_csr (not used so I assume it ackowledges 
            ; the interrupt ?) 
            ;------------------------------------------------
inCaptInt1  ldx     t3_clock1               ; Get current coil clock value when the cas edge changed?
            ldab    t1_csr                  ; Acknowledge cas input capture interrupt?                                                                                                                              

            ;--------------------------------------------------------
            ; Update t1_lastCas for eventual aiflow calculation
            ;--------------------------------------------------------
            ldd     t1_inCapt               ; Get cas input timer capture high/low                                                                                            
            std     t1_lastCas              ; store it here                                                                                                               

            ;------------------------------------------------
            ; Update temp20 assuming interrupt is from t2
            ; will be changed later if assumption was wrong
            ;------------------------------------------------
            ldd     t3_clock2               ; Get current counter value
            std     temp20                  ; temp20 = t3_clock2                                                                                                                            

            ;-------------------------------------------
            ; Branch to rising or falling edge section 
            ; depending on the interrupt source
            ;-------------------------------------------
            brclr   t1_csr, #$02, casRiseProc ; Branch if this is the cas rising edge
            jmp     casFallProc               ; Branch to cas failling edge section



;******************************************************************
;
;
; Section processing the CAS interrupt on the rising edge
;   
;;
;
;******************************************************************
            ;-------------------------------------------------------------------------
            ; Check which of t3_clock1 or t3_clock2 should be used?
            ; Not sure what that bit means???????????
            ;-------------------------------------------------------------------------
casRiseProc brclr   t3_csr0, #$10, L1654    ; Branch if we should use t3_clock2, nothing to do, that's what we assumed above

            ;-------------------------------------------------------------------------
            ; t3_clock1 should be used, our assumption that it was
            ; t3_clock2 was wrong, update d and  temp20 with the correct values
            ;-------------------------------------------------------------------------
            xgdx                            ; d = t3_clock1
            std     temp20                  ; temp20 = t3_clock1

            ;-------------------------------------------------------------
            ; Branch to rest of code if the time between CAS
            ; interrupts makes sense (rpm is not too high...)
            ;
            ; The time measured here is the time in-between cas
            ; pulses since it is measured from the falling edge to the 
            ; rising edge. Since this time correspond to 110deg
            ; then the 1ms below correspond to 360/110*1ms = 3.27ms 
            ; per rotation which correspond to 18333rpm. The threshold of
            ; 1ms or 0.5 ms (18333 or 23333rpm) on the cas rising and falling 
            ; edge section is not the same and it might be due to the fact
            ; that on the cas falling edge, we measure a smaller interval 
            ; (70deg instead of 110deg) and therefore the uncertainty is 
            ; higher???
            ;-------------------------------------------------------------
L1654       subd    casFallTime0            ; d = t3_clock1 - casFallTime0
            cmpd    #$00fa                  ; 1ms at 250KHz                                                                                                                             
            bcc     L1655                   ; Branch if (t3_clock1 or  t3_clock2 - casFallTime0) >= $00fa

            ;------------------------------------------------
            ; RPM seems too high to make sense, check if it is
            ; not instead because RPM is so low that the 16 bit 
            ; counter subtraction above rolled-over.
            ;
            ; Branch to rest of code if the T200_casFall timer shows
            ; that rpm is very low... 
            ;------------------------------------------------
            ldaa    T200_casFall            ;                                                                                                                             
            cmpa    #$0e                    ; 70ms at 200Hz                                                                                                                             
            bcs     L1655                   ; branch if T200_casFall<70ms, T200_casFall is init with 265ms, the time between interrupt is very high                                                                                                                            

            ;-------------------------------------------------------------
            ; Time between interrupts doesn't make sense, just ignore it
            ; Return from interrupt
            ;-------------------------------------------------------------
            rti                             ;                                                                                                                            

            ;---------------------------------------------------------------
            ; Update temp22:temp23 = Tcas measured on the cas rising edge
            ;---------------------------------------------------------------
L1655       ldd     temp20                  ; D = temp20
            subd    casRiseTime0            ; D = temp20-casRiseTime0(old counter) = Tcas = 250000/2/(rpm/60)                                      
            std     temp22                  ; temp22:temp23 = Tcas (temp22 is not dedicated for that purpose...)                                 

            ;--------------------------------
            ; Validate temp22:temp23 = Tcas
            ;--------------------------------
            ldab    T200_casRise            ;                                
            beq     L1656                   ; Branch if timer expired (very long Tcas...)                            
            tsta                            ;                             
            bmi     L1657                   ; Branch if Tcas/256 >= 128 (rpm<229)                             
            cmpb    #$0e                    ;                             
            bhi     L1657                   ; Branch if T200_casRise > $0e (70ms)                             
L1656       ldd     #$ffff                  ; Use max Tcas                              
            std     temp22                  ; store Tcas

            ;----------------------------------------------
            ; Section to calculate new casFlags0 value but do 
            ; not store it now. It will be stored once the 
            ; interrupt is validated
            ;----------------------------------------------
            ;----------------------------------------------
            ; First transfer some bits to "old" positions 
            ; and assume some bits will be set...
            ;----------------------------------------------
L1657       ldaa    casFlags0               ; a = casFlags0                              
            anda    #$05                    ; a = casFlags0 & 00000101 (keep some old bits)                            
            asla                            ; Move the old bits to the "old" positions                            
            oraa    #$35                    ; preload some bits (00110101)

            ;--------------------------------------------------
            ; Set flag if timing adjustement mode is active
            ;--------------------------------------------------
            brclr   timAdjFlags, #$80, L1658 ; Branch if we are not in timing adjustement mode                               
            oraa    #$40                     ; a = (casFlags0 & 00001001)*2 | 01110101                            

            ;-------------------------------------------------
            ; Reset some new casFlags0 bits depending on rpm
            ;-------------------------------------------------
L1658       ldx     temp22                   ; x = temp22:temp23 = Tcas                             
            cpx     #$061a                  ; 4801rpm                                   
            bcs     L1662                   ; Branch if rpm(Tcas) >  4801rpm                                        
            anda    #$df                    ; Reset 00100000                                        
            cpx     #$1081                  ; 1775rpm                                    
            bcs     L1659                   ; Branch if rpm(Tcas) >  1775rpm
            anda    #$fb                    ; Reset 00000100                                        
L1659       cpx     #$1306                  ; 1540rpm                                    
            bcs     L1660                   ; Branch if rpm(Tcas) >  1540rpm                                           
            anda    #$ef                    ; reset 00010000                                        

            ;---------------------------------------
            ; At this point rpm(Tcas) <= 4801rpm
            ; Choose rpm threshold with hysteresis
            ;---------------------------------------
L1660       ldab    #$49                    ; b = $49 (401rpm)                            
            bita    #$02                    ;                              
            bne     L1661                   ; Branch if bit was already set                             
            ldab    #$3a                    ; use lower threshold if bit alread set b = $3a (505rpm)                             

            ;---------------------------------------------------------------------
            ; Reset flag bit if we are above/below threshold, with hysteresis
            ;---------------------------------------------------------------------
L1661       cmpb    temp22                  ;                              
            bhi     L1662                   ; Branch if rpm(Tcas) < b (401rpm or 505rpm)                             
            anda    #$fe                    ; Reset 00000001                      
                  
            ;-----------------------------------------------------------
            ; Store new value of casFlags0 in temp location for now
            ;-----------------------------------------------------------
L1662       staa    temp24                  ; Store new casFlags0 in temp memory for now
            
            ;--------------------------------------------------------------------
            ; At this point, we will check the CAS signal to make sure it stays
            ; set until 56us after the start of the interrupt. I guess this might
            ; be to filter eventual glitches in the CAS signal
            ;--------------------------------------------------------------------
            ldd     temp20                  ;                                   
            addd    #$000e                  ; d = StartInterruptTime + $0e (56us)                              
L1663       brclr   port5, #$01, L1664      ; Branch as long as CAS bit is clear (CAS signal is set)
            rti                             ; CAS bit was set, Bail of interrupt
L1664       cmpd1   t3_clock1               ; Compare current time to time stored when we started the interrupt processing                                 
            bpl     L1663                   ; Loop if t3_clock1 < (temp20 + $0e (56us)), i.e. if its been less than 56us since interrupt was called



;******************************************************************
;
; Interrupt was valid
; Proceed with processing stuff on the CAS rising edge
;
;
;******************************************************************
            ;------------------------------------------
            ; Update p4Latched
            ; (get our own copy of port4, we don't want 
            ; changes during processing) 
            ;------------------------------------------
            ldaa    port4                   ;                              
            staa    p4Latched               ;                                  

            ;-----------------------
            ; Update casRiseTime0 
            ;-----------------------
            ldd     temp20                  ; d = temp20                                   
            std     casRiseTime0            ; casRiseTime0 = time at interrupt start 

            ;--------------------------------------
            ; Finally store the new casFlags0 value  
            ; (we now know interrupt was valid...)
            ;--------------------------------------
            ldaa    temp24                  ;                              
            staa    casFlags0               ;                              

            ;---------------------------------------------------------
            ; Reset flag ignFallFlags.0
            ;---------------------------------------------------------
            andm    ignFallFlags, #$fe             ;                                

            ;---------------------------------------------------------
            ; restart T200_casRise timer to 175ms
            ;---------------------------------------------------------
            ldaa    #$35                    ; 175ms                             
            staa    T200_casRise            ;                              

            ;------------------------------------
            ; Store current TDC state in temp24
            ;------------------------------------
            ldaa    port3                   ;                             
            anda    #$04                    ; Keep only TDC bit                           
            staa    temp24                  ; temp24.2 = TDC bit

            ;-----------------------------------------------
            ; Toggle tdcMask0:tdcMask1 (between $0402 and $0204)
            ;-----------------------------------------------
            ldd     #$0402                  ;                              
            brset   tdcMask0, #$02, L1665   ; Branch if old tdcMask0.1 is set
            ldd     #$0204                  ;                               
L1665       std     tdcMask0                ; Store new value
                   
            ;-----------------------------------------------------
            ; Only execute the following section if the TDC signal 
            ; did not change. Why? we just stored it 
            ; a few lines earlier????? and if we really are on the
            ; CAS rising edge then TDC cannot change at this time...
            ;
            ; Maybe this is some kind of safety/glitch/noise 
            ; safety precaution. TDC signal could get corrupted
            ; when the engine is cranking, low battery...? 
            ;-----------------------------------------------------
            ldaa    temp24                  ; a.2 = TDC bit, we just stored this value a few lines earlier, probability of it changing must be very low? I guess we MUST ensure temp24 is in synch with port3.2?????
            eora    port3                   ; a.2 = oldTdcbit eor newTdcBit                             
            anda    #$04                    ; Keep only TDC bit
            bne     L1671                   ; branch if TDC bit changed, very low probability or even impossible if we really are on the CAS rising edge????

            ;--------------------------------------------------------------
            ; TDC bit did not change (normal case), execute the section
            ;--------------------------------------------------------------
            ;-----------------------
            ; First check start key
            ;-----------------------
            brclr   port3, #$40, L1668      ; Branch if key is in start position                                

            ;----------------------------------------------------
            ; Key is not in start
            ; Increment tdcCasCount up to a max of 6 
            ;----------------------------------------------------
            ldaa    tdcCasCount             ; a = old tdcCasCount                             
            inc     tdcCasCount             ; tdcCasCount += 1
            cmpa    #$05                    ;                             
            bls     L1666                   ; branch if old tdcCasCount <=5 (new one is then <=6, no need to check max)                            
            ldaa    #$06                    ; use max of 6                            
            staa    tdcCasCount             ; store new value                             

            ;----------------------------------------------------
            ; Load b=$02 or $04 depending on TDC current value
            ;----------------------------------------------------
L1666       ldab    #$02                    ; b = $02                            
            brclr   temp24, #$ff, L1667     ; Branch if TDC bit is 0 (TDC signal active)                              
            ldab    #$04                    ; b = $04                            

            ;------------------------------------------------------------
            ; At this point b=$02 if TDC signal is active, $04 otherwise
            ;------------------------------------------------------------
L1667       cmpb    tdcMask0                ;                              
            beq     L1671                   ; Branch if b = tdcMask0 (tdcMask0 is in synch with TDC???)                             

            ;----------------------------------------------------
            ; b != tdcMask0, we are out of synch, reinstate old 
            ; tdcCasCount and branch to re-init tdcMask0
            ;----------------------------------------------------
            deca                            ;                            
            staa    tdcCasCount             ; tdcCasCount -= 1                                   
            cmpa    #$03                    ;                            
            beq     L1669                   ; Branch if tdcCasCount=3                            
            bpl     L1671                   ; Branch if tdcCasCount>3                           

            ;-----------------------------------------------
            ; Key in start or tdcCasCount<3, restart synch 
            ; from scratch, i.e. tdcCasCount=0
            ;-----------------------------------------------
L1668       clra                            ;                             
            staa    tdcCasCount             ; tdcCasCount = 0                                   

            ;------------------------------------------------------------------
            ; Init tdcMask0 with $0204 if TDC is active $0402 otherwise
            ;------------------------------------------------------------------
L1669       ldd     #$0402                  ;                               
            brset   temp24, #$ff, L1670     ; Branch if TDC bit is 1 (TDC signal inactive)                               
            ldd     #$0204                  ;                               
L1670       std     tdcMask0                ;                              

            ;---------------------------------------------
            ; Decide if we are going to calculate timing 
            ; or use fix timing of 5deg BTDC 
            ;---------------------------------------------
L1671       ldx     #$002a                   ; x = $002a in case we have to bail to L1679                               
            brclr   tdcCasCount, #$fe, L1672 ; Branch if tdcCasCount = 0 or 1
            brclr   casFlags0, #$40, L1673   ; Branch if timing adjustment mode is not active
                                         
            ;-----------------------------------------------------------------------
            ; tdcCasCount = 0 or 1 or timing adjustment mode is active
            ; Use default timing of 5 deg BTDC (or 4.75deg? close enough)
            ;-----------------------------------------------------------------------
L1672       ldab    #$a0                     ; Use default value of tim61 = $a0 = 160 = 4.75deg BTDC (tech manual says 5deg BTDC)                             
            bra     L1679                    ;                             

            ;------------------------------------
            ; tdcCasCount >= 2 and casFlags0.6 = 0 
            ; Reset knockSum if knockSum>43 ???
            ;------------------------------------
L1673       ldab    knockSum                 ;                                
            cmpb    #$2b                     ;                            
            bls     L1674                    ; Branch if knockSum<= $2b (43)                            
            clrb                             ;                            
            stab    knockSum                 ;
                                            
            ;---------------------------------------------------------------
            ; Compute the new target timing tim61Tot1 
            ;
            ;      tim61Tot1 = temp24 = min(knockSum+tim61Tot0, $bc)
            ;
            ; tim61Tot1 is therefore tim61Tot0 which is further retarded
            ; by a number of degrees equal to knockSum. Maximum value is
            ;
            ;       max = $bc = 188 =  256 * 66deg / 90
            ;
            ; which is +5deg ATDC since it is referenced to 61degBTDC
            ;---------------------------------------------------------------
L1674       addb    tim61Tot0                ; b = knockSum + tim61Tot0                            
            bcs     L1675                    ; Branch if overflow                            
            cmpb    #$bc                     ; Check for max                           
            bcs     L1676                    ; Branch if knockSum+tim61Tot0 < $bc                            
L1675       ldab    #$bc                     ; Use max              
L1676       stab    temp24                   ; temp24 = tim61Tot1 = min(knockSum+tim61Tot0, $bc)

            ;-------------------------------------------------------------
            ; Compute the new timing newTim61 we are going to apply 
            ;
            ; We start with tim61Tot1 computed above but the code below 
            ; seem to limit the rate of change of the timing by 22.5 
            ; deg per iteration ($40). 
            ;-------------------------------------------------------------
            ldd     timCas0                 ; d = timCas0:timCas1                            
            subd    #$002a                  ; d = timCas0:timCas1 - $002a                              
            cmpb    temp24                  ;                              
            bcc     L1677                   ; Branch if timCas0:timCas1 - $002a >= tim61Tot1

            ;----------------------------------------------------
            ; low(timCas0:timCas1 - $002a) < tim61Tot1
            ;----------------------------------------------------
            addb    #$40                    ; b = timCas0:timCas1 - $002a + $40                            
            bcs     L1678                   ; Branch if overflow                            
            cmpb    temp24                  ;                               
            bcs     L1679                   ; Branch if  timCas0:timCas1 - $002a + $40 < tim61Tot1
            bra     L1678                   ; Use tim61Tot1                            

            ;----------------------------------------------------
            ; low(timCas0:timCas1 - $002a) >= min(knockSum+tim61Tot0, $bc)
            ;----------------------------------------------------
L1677       subb    #$40                    ; b = timCas0:timCas1 - $002a - $40                           
            bcs     L1678                   ; Branch if  timCas0:timCas1 - $002a - $40 < 0                            
            cmpb    temp24                  ;                              
            bcc     L1679                   ; Branch if timCas0:timCas1 - $002a - $40 >= tim61Tot1

            ;-------------------
            ; Use tim61Tot1 
            ;-------------------
L1678       ldab    temp24                  ; Use tim61Tot1                             
            ldx     #$002a                  ; reload x = $002a (why, did not change)                             

            ;-----------------------------------------------------------------------------------------------
            ;
            ; At this point x = $002a, b = newTim61
            ;
            ; Where newTim61 is tim61Tot1 with a limit on its 
            ; rate of change (21.5deg/iteration max):
            ;
            ;    if oldtim61 >= tim61Tot1                    if old timing is more retarded
            ;           if oldtim61 - $40 < 0                    if oldtim61< 22.5deg (minimum allowed)
            ;                tim61Tot1                               Use new value
            ;           else if oldtim61 - $40 >= 0               else if oldtim61 >= 22.5deg (minimum allowed)
            ;                max(oldtim61 - $40, tim61Tot1)          Use the one with the least amount of change... 
            ;
            ;   else if oldtim61 < tim61Tot1                  else if old timing is less retarded
            ;            if oldtim61 + $40 > 256                 if oldtim61 > 67.5deg (max allowed)  
            ;                tim61Tot1                               Use new value
            ;            else if oldtim61 + $40 < 256            else if oldtim61 < 67.5deg (max allowed)
            ;                min(oldtim61 + $40, tim61Tot1)          Use the one withe the least amount of change...
            ;
            ; where tim61Tot1 = min(knockSum+tim61Tot0, $bc)
            ;       oldtim61 = [timCas0:timCas1] - $002a
            ;
            ;-----------------------------------------------------------------------------------------------
            ;----------------------------------------------------
            ;
            ; Update tim61 and [timCas0:timCas1]
            ;     timCas0:timCas1 = tim61 + $002a
            ;                 = 256 * (61 - degAdv) / 90 + 42
            ;                 = 256 * ((61 - degAdv) + 14.77) / 90
            ;                 = 256 * (75.77 - degAdv) / 90
            ;
            ; Since each CAS pulse rising edge is at 75deg BTDC,  
            ; [timCas0:timCas1] is the timing referenced to  
            ; the CAS pulse rising edge
            ;----------------------------------------------------
L1679       abx                            ; x = tim61 + $002a                            
            stx     timCas0                ; [timCas0:timCas1] = tim61 + $002a
            stab    tim61                  ;                              

            ;----------------------------------------------------------------------
            ; Branch to re-init timing stuff if rpm<505 or key in start position
            ;----------------------------------------------------------------------
            brclr   casFlags0, #$01, L1680  ; Branch to re-init timing stuff if rpm<505, with hysteresis                              
            brclr   port3, #$40, L1680      ; Branch to re-init timing stuff if key in start position                               

            ;---------------------------------------------------
            ; At this point rpm>505 and key is not is start
            ;
            ; branch to normal code if rpm>505rpm the previous time
            ; else update TcasLast0 and re-init timing stuff 
            ;---------------------------------------------------
            brset   casFlags0, #$02, L1681  ; Branch to normal code if rpm>=505rpm the previous time                               
            jsr     L1650                   ; d = abs(Tcas - TcasLast0) - Tcas * $30/256
            bcc     L1680                   ; Branch to re-init timing stuff if abs(Tcas - TcasLast0) >= Tcas * $30//256, i.e. abs(Tcas - TcasLast0)/Tcas >= 18.75%
            ldx     temp22                  ; abs(Tcas - TcasLast0)/Tcas < 18.75%
            stx     TcasLast0               ; Update TcasLast0
            jmp     L1710                   ; Jump to re-init timing stuff

            ;------------------------------
            ; Jump to re-init timing stuff
            ;------------------------------
L1680       jmp     L1709                                                 

            ;--------------------------------------------
            ; Section to perform some additional Tcas 
            ; validation when  rpm(Tcas) <= 4801rpm
            ;--------------------------------------------
L1681       brclr   casFlags0, #$20, L1682  ; Branch if rpm(Tcas) <= 4801rpm
            jmp     L1685                   ; Bail to next section

            ;---------------------------
            ; rpm(Tcas) <= 4801rpm
            ;---------------------------
            ;---------------------------
            ; Check rpm
            ;---------------------------
L1682       ldaa    temp22                  ; a = Tcas/256                             
            cmpa    #$14                    ; 1464rpm                            
            bls     L1683                   ; Branch if rpm(Tcas) >= 1464rpm
                                         
            ;----------------------------------------------------
            ; rpm(Tcas) < 1464
            ;----------------------------------------------------
            ldx     timCas0                 ; x = timCas0                              
            cpx     #$00ca                  ;                               
            bhi     L1683                   ; branch if timCas0 > $ca (4deg BTDC)                               
            jsr     L1650                   ; d = abs(Tcas - TcasLast0) - Tcas * $30/256                             
            bcs     L1683                   ; Branch if result was negative                             
            jmp     L1709                   ;                              

            ;----------------------------------------------------
            ;    timCas0 > $ca (4deg BTDC)
            ; or abs(Tcas - TcasLast0) - Tcas * $30/256 < 0
            ; or rpm(Tcas) >= 1464
            ;----------------------------------------------------
L1683       ldd     temp22                  ; d = Tcas                             
            cmpa    #$19                    ; 1171rpm                       
            bcc     L1685                   ; Branch if rpm(Tcas) >= 1171rpm
            lsrd                            ;                             
            lsrd                            ;                             
            lsrd                            ;                             
            lsrd                            ;                             
            lsrd                            ;                             
            lsrd                            ; d = Tcas/64                            
            std     temp20                  ; temp20 = Tcas/64                                   

            ldd     TcasLast0               ; d = TcasLast0                             
            subd    temp22                  ; d = TcasLast0 - Tcas                              
            bcc     L1684                   ; Branch if result positive (rpm is increasing????)                            

            ldd     temp22                  ;                              
            subd    TcasLast0               ; d =                              
            subd    temp20                  ; d = Tcas - TcasLast0 - Tcas/64                                    
            bcs     L1685                   ; Branch if result negative                              

            ;------------------------------------------------------------
            ; d = Tcas - TcasLast0 - Tcas/64 >= 0
            ; Multiply result d = v1:v0 by $80/$80 = 1.0
            ;
            ; Maybe I miss something but this is useless. My guess
            ; is that the multiplicative factor (1.0 in this case) was 
            ; configurable but in the end they chose 1.0 which renders this
            ; code useless???
            ;
            ;------------------------------------------------------------
            stab    temp24                  ; save b                              
            ldab    #$80                    ; b = $80                             
            mul                             ; d = v1*$80                            
            xgdx                            ; x = v1*$80                            
            ldaa    temp24                  ; a = v0                              
            ldab    #$80                    ; b = $80                            
            mul                             ; d = v0 * $80                            
            tab                             ; b = v0 * $80/256                            
            abx                             ; x = v1*$80 +  v0 * $80/256 = [v1:v0] * $80/256
            xgdx                            ; d = $80/256 * (Tcas - TcasLast0 - Tcas/64)                              
            asld                            ; d = $80/128 * (Tcas - TcasLast0 - Tcas/64) = Tcas - TcasLast0 - Tcas/64                            

            ;---------------------------------------------------------------------------
            ; Branch to re-init if Tcas + (Tcas - TcasLast0 - Tcas/64)  > 32767
            ;                              (TcasLast0 - Tcas - Tcas/64) > Tcas
            ;                                       (TcasLast0 - Tcas ) > Tcas(1+1/64)
            ;                                  (TcasLast0 - Tcas )/Tcas > 101.6%
            ;
            ; We are basically checking if Tcas increased by more than 101.6%
            ;---------------------------------------------------------------------------
            bcs     L1687                   ; Branch to re-init if overflow                              
            addd    temp22                  ; d = Tcas + (Tcas - TcasLast0 - Tcas/64) = Tcas(2-1/64) - TcasLast0                             
            bcs     L1687                   ; Branch to re-init if overflow                             
            bra     L1686                   ; Branch to code continuation
                                          
            ;----------------------------------------------------
            ; (TcasLast0 - Tcas) > 0 (rpm is increasing),
            ;
            ; Check if  
            ;               TcasLast0 - Tcas < Tcas/64
            ;        (TcasLast0 - Tcas)/Tcas < 1/64
            ;        (TcasLast0 - Tcas)/Tcas < 1.6%
            ; 
            ; We are basically checking if Tcas changed by less than 1.6%
            ; This also correspond to a change of rpm of 1.6%
            ;----------------------------------------------------
L1684       subd    temp20                  ; d = TcasLast0 - Tcas - Tcas/64                                    
            bcs     L1685                   ; Branch if result negative, i.e. change in Tcas is less than 1/64                            

            ;------------------------------------------------------------
            ; At this point, rpm increased by more than 1.6%
            ; and d = TcasLast0 - Tcas - Tcas/64 >= 0
            ; Multiply result d = v1:v0 by $80/$80 = 1.0
            ;
            ; Maybe I miss something but this is useless. My guess
            ; is that the multiplicative factor (1.0 in this case) was 
            ; configurable but in the end they chose 1.0 which renders this
            ; code useless???
            ;------------------------------------------------------------
            stab    temp24                  ; temp24 = v0
            ldab    #$80                    ; b = $80                           
            mul                             ; d = $80 * v1                            
            xgdx                            ; x = $80 * v1                           
            ldaa    temp24                  ; a = v0
            ldab    #$80                    ; b = $80                             
            mul                             ; d = $80 * v0                            
            tab                             ; b = $80/256 * v0                             
            abx                             ; x = $80 * v1 + $80/256 * v0 = $80/256 * [v1:v0]
            xgdx                            ; d = $80/256 * (TcasLast0 - Tcas - Tcas/64)
            asld                            ; d = $80/128 * (TcasLast0 - Tcas - Tcas/64) = (TcasLast0 - Tcas - Tcas/64)
                                         
            ;-----------------------------------------------------------------------------
            ; Branch to re-init if  Tcas - (TcasLast0 - Tcas - Tcas/64) < 0???
            ;                              (TcasLast0 - Tcas - Tcas/64) > Tcas
            ;                                       (TcasLast0 - Tcas ) > Tcas(1+1/64)
            ;                                  (TcasLast0 - Tcas )/Tcas > 101.6%
            ;
            ; We are basically checking if Tcas increased by more than 101.6%
            ;-----------------------------------------------------------------------------
            bcs     L1687                   ; Branch to re-init if overflow
            std     temp20                  ; temp20 = TcasLast0 - Tcas - Tcas/64                                   
            ldd     temp22                  ; d = Tcas                             
            subd    temp20                  ; d = Tcas - (TcasLast0 - Tcas - Tcas/64) =  Tcas(2+1/64) - TcasLast0 
            bcs     L1687                   ; Branch to re-init if Tcas increased by more than 101.6%
            bra     L1686                   ; Branch to code continuation

            ;----------------------------------------
            ; Update TcasNew0:TcasNew1
            ; Check if Tcas is within normal range
            ; Branch to re-init if not
            ;----------------------------------------
L1685       ldd     temp22                  ; d = Tcas                              
L1686       std     TcasNew0                ; [TcasNew0:TcasNew1] = Tcas                             
            bmi     L1687                   ; Branch if sign bit set, Tcas at max value, jump to re-init???                             
            cmpd    #$0146                  ; Compare to min (max of 23006rpm??)                               
            bcc     L1688                   ; Branch if d >= min (rpm < 23006rpm)                              
L1687       jmp     L1709                   ; rpm >= 23006rpm, jump to re-init

            ;-------------------------------
            ; Tcas is within normal range
            ; Update TcasLast0
            ;-------------------------------
L1688       ldd     temp22                   ;                              
            std     TcasLast0                ;
                                                            
            ;--------------------------------------------------------
            ; Compute d = [TcasNew0:TcasNew1] * [timCas0:timCas1]/256
            ; We assume timCas0 can only be 0 or 1 
            ; (Higher values are impossible, huge timing retard...)
            ;--------------------------------------------------------
            ldab    timCas1                 ;                              
            ldaa    TcasNew1                ;                              
            mul                             ; d = timCas1 * TcasNew1                            
            staa    temp20                  ;                                    
            ldaa    timCas1                 ;                              
            ldab    TcasNew0                ;                              
            mul                             ; d = timCas1 * TcasNew0                             
            addb    temp20                  ;                                    
            adca    #$00                    ; d = [TcasNew0:TcasNew1] * timCas1/256
            brclr   timCas0, #$ff, L1689    ; Branch if timCas0=0
            addd    TcasNew0                ; d = [TcasNew0:TcasNew1] * [timCas0:timCas1]/256

            ;--------------------------------------------------------------------------------------
            ; At this point d = [TcasNew0:TcasNew1] * [timCas0:timCas1]/256
            ; Update ignRelTime0:ignRelTime1 (ignition timing measured in time instead of degrees)
            ;
            ;       ignRelTime0:ignRelTime1 = [TcasNew0:TcasNew1]/2 * [timCas0:timCas1]/256 - $0012
            ;
            ; timCas0/256 is a ratio from 0 to 1 corresponding to 0 to 90deg, since Tcas 
            ; correspond to 180 deg, Tcas/2 * timsCas0/256 is equal to the "timing time" referenced
            ; to 75 BTDC
            ;
            ; ignRelTime0:ignRelTime1 is therefore the ignition timing (in timer time) 
            ; referenced to 75BTDC and minus 72us
            ;--------------------------------------------------------------------------------------
L1689       lsrd                            ; d = [TcasNew0:TcasNew1] * [timCas0:timCas1]/256/2
            subd    #$0012                  ; d = [TcasNew0:TcasNew1] * [timCas0:timCas1]/256/2 - $0012
            bcc     L1690                   ; Branch if no underflow                              
            clra                            ; use min of 0                            
            clrb                            ; use min of 0                            
L1690       std     ignRelTime0             ; [ignRelTime0:ignRelTime1] = [TcasNew0:TcasNew1] * [timCas0:timCas1]/256/2 - $0012

            ;----------------------------------------------------
            ; Check if the current coil is already energized
            ;----------------------------------------------------
            ldaa    port5                   ;                              
            anda    tdcMask0                ; $02 or $04                              
            beq     L1698                   ; Branch if coil is already energized

            ;----------------------------------------------------------------------
            ; Coil is not yet energized, section to calculate energization time
            ; and schedule the energization...
            ;----------------------------------------------------------------------
            ;-----------------------------------------
            ; Init enerFlags to $02 since we know we 
            ; are going to schedule energization
            ;-----------------------------------------
            ldaa    #$02                    ; a = $02                             
            staa    enerFlags               ; enerFlags = $02 
                                        
            ;-----------------------------------------------------------------------------
            ; If rpm(Tcas) > 1775rpm and previously rpm(Tcas) >  1775rpm
            ; The we can  use enerLenX0 (already calculated in previous iteration?)
            ;-----------------------------------------------------------------------------
            brclr   casFlags0, #$04, L1691  ; Branch to compute energization time if rpm(Tcas) <=  1775rpm
            ldd     enerLenX0               ; d = [enerLenX0:enerLenX1]
            brset   casFlags0, #$08, L1695  ; Branch to use enerLenX0 if rpm(Tcas) >  1775rpm the previous time

            ;--------------------------------------------------------------------------
            ;    rpm(Tcas) <=  1775rpm
            ; or rpm(Tcas) >  1775rpm  but  previously rpm(Tcas) <=  1775rpm
            ; We need to compute the energization time
            ;
            ; Check if we can use a short or long energization time??? not sure
            ; why 
            ;--------------------------------------------------------------------------
L1691       ldd     TcasNew0                ; d = TcasNew0
            subd    #$1130                  ; d = TcasNew0 - $1130  (18ms????) (check for rollover???)
            bcc     L1692                   ; Branch if no underflow                             

            ;------------------------------------------------------------------
            ; Underflow, use a shorter fixed value of d = 16*enerLen
            ;------------------------------------------------------------------
            ldaa    enerLen                 ; a = enerLen
            clrb                            ; d = enerLen*256                             
            lsrd                            ;                              
            lsrd                            ;                              
            lsrd                            ;                              
            lsrd                            ; d = enerLen*256/16 = 16*enerLen                              
            bra     L1695                   ; Bail                              

            ;----------------------------------------------------------------------------------------------
            ; TcasNew0 >= $1130, i.e. rpm <= 1704rpm,
            ;
            ; Compute  a longer energization time????
            ;
            ;   d = 16*enerLen + TcasNew0/2 * (timCas0 - $00ca + $04)/256/2    + (TcasNew0 - $1130)/16
            ;     = 16*enerLen + TcasNew0/2 * (timCas0 - 71deg + 1.4deg)/256/2 + (TcasNew0 - $1130)/16
            ;
            ;----------------------------------------------------------------------------------------------
L1692       lsrd                            ;                              
            lsrd                            ;                              
            lsrd                            ;                              
            lsrd                            ; d = (TcasNew0 - $1130)/16
            std     temp22                  ; temp22 = (TcasNew0 - $1130)/16
            ldd     timCas0                 ; d = timCas0                              
            subd    #$00ca                  ; d = timCas0 - $00ca (71deg)                              
            bls     L1694                   ; Branch if timCas0 <= $00ca (71deg)                             
            addb    #$04                    ; b = timCas0 - $00ca + $04                            
            ldaa    TcasNew0                ; a = TcasNew0/256                             
            mul                             ; d = TcasNew0/256 * (timCas0 - $00ca + $04)                             
            lsrd                            ;                             
            lsrd                            ; d = TcasNew0/256/4 * (timCas0 - $00ca + $04)                            
            tsta                            ;                             
            beq     L1693                   ; Branch if a=0 (result <= $ff)                             
            ldd     #$0100                  ; Use max of $0100                              
L1693       addd    temp22                  ; d = TcasNew0/256/4 * (timCas0 - $00ca + $04) + (TcasNew0 - $1130)/16
            std     temp22                  ; temp22 = TcasNew0/256/4 * (timCas0 - $00ca + $04) + (TcasNew0 - $1130)/16
L1694       ldaa    enerLen                 ; a = enerLen                             
            clrb                            ; d = enerLen*256                            
            lsrd                            ;                             
            lsrd                            ;                             
            lsrd                            ;                             
            lsrd                            ; d = enerLen*256/16                             
            addd    temp22                  ; d = enerLen*16 + (TcasNew0 - $1130)/16 + [TcasNew0/2 * (timCas0 - $00ca + $04)/256/2]
L1695       std     temp22                  ; temp22 = enerLen*16 + (TcasNew0 - $1130)/16 + [TcasNew0/2 * (timCas0 - $00ca + $04)/256/2]


            ;---------------------------------------------------------------------------------------
            ; At this point temp22 = energizationDuration contains the energization time, 3 cases:
            ; 
            ;       temp22 = 16*enerLen 
            ;    or temp22 = 16*enerLen + (TcasNew0 - $1130)/16 + [if timing >71deg, TcasNew0/2 * (timCas0 - $00ca + $04)/256/2]
            ;    or temp22 = enerLenX0:enerLenX1
            ;
            ;
            ; Compute temp22 = the absolute time (timer clock) at 
            ; which the coil needs to start being energized
            ;---------------------------------------------------------------------------------------
            ldd     ignRelTime0             ;                              
            subd    temp22                  ; d = ignRelTime0 - energizationDuration
            addd    casRiseTime0            ; d = casRiseTime0 + ignRelTime0 - energizationDuration
            std     temp22                  ; temp22 = casRiseTime0 + ignRelTime0 - energizationDuration

            ;---------------------------------------------------------------------
            ; Check if the energization time of next coil is sufficientlty far
            ; away from the preceeding coil ignition time. If not then use
            ; an energization time as close as possible to that ignition time???
            ;---------------------------------------------------------------------
            ldd     ignTime0                ; d = ignTime0:ignTime1                            
            addd    #$00fa                  ; d = ignTime0 + $fa (1ms)                            
            cmpd1   temp22                  ;                             
            bmi     L1696                   ; Branch if ignTime0 + $fa < energization time, i.e. energization is sufficiently far away from the ignition of the preceeding cylinder, less than 1ms
            std     temp22                  ; Replace energization time with ignTime0 + $fa 

            ;-----------------------------------------
            ; Check that coil energization is 
            ; sufficiently in the future to be valid
            ;-----------------------------------------
L1696       ldd     t3_clock1               ; d = t3_clock1                                   
            addd    #$000a                  ; d = t3_clock1 + $0a (40usec)                             
            xgdx                            ; x = t3_clock1 + $0a                            
            cpx     temp22                  ;                              
            bpl     L1697                   ; Branch to use t3_clock1 + $0a if energization is "in the past"
            ldx     temp22                  ; Energization time is valid, use it

            ;---------------------------------------------------------------------------
            ; Schedule coil energization interrupt time and update enerAbsTime0 with it
            ;---------------------------------------------------------------------------
L1697       stx     t3_outCmpWr             ; Schedule interrupt time on first output compare register
            ldaa    t3_csr1                 ; Go to next output compare register                                    
            stx     t3_outCmpWr             ; Schedule interrupt time on second output compare register
            stx     enerAbsTime0            ; Save energization interrupt time in memory
                                         
            ;-------------------------------------------------------------------------
            ; Reset the bit for the corresponding cylinder in control register
            ; in order to energize the proper coil at the scheduled time
            ;
            ; Bits in t3_csr0 are offset by 1 bit compared to tdcMask0, so shift 
            ; tdcMask0 by 1 bit and then reset that bit in t3_csr0...  
            ;-------------------------------------------------------------------------
            ldaa    tdcMask0                ; a = $02 or $04                             
            asla                            ; a = $04 or $08 (shift tdcMask0 bit by 1 to have the corresponding bit in t3_csr0)                             
            coma                            ; a = ~($04 or $08)                            
            anda    t3_csr0                 ; reset that bit in t3_csr0 (energize coil at scheduled time)                            
            staa    t3_csr0                 ; Update t3_csr0 
            bra     L1699                   ; Bail to  ignition section                             

            ;---------------------------------------------------------
            ; Coil is already energized
            ;
            ; Flush the first output compare register (write the 
            ; fartest possible time) since we don't need an interrupt
            ; to energize it???. Also make sure enerFlags = 1 to indicate 
            ; coil is energized?
            ;---------------------------------------------------------
L1698       ldx     t3_clock1               ; x = t3_clock1                                   
            dex                             ; x = t3_clock1-1                            
            stx     t3_outCmpWr             ; Re-init first output compare register with t3_clock1-1, the fartest time possible
            ldaa    #$01                    ; a = 1                            
            staa    enerFlags               ; enerFlags = 1                             

            ;------------------
            ; Ignition section
            ;------------------
            ;-------------------------------------------------------------------
            ; Compute ignTime0 = absolute ignition time (referenced to timer clock)
            ;-------------------------------------------------------------------
L1699       ldd     ignRelTime0             ; d = ignRelTime0:ignRelTime1                              
            addd    casRiseTime0            ; d = ignRelTime0 + casRiseTime0                                       
            std     ignTime0                ; ignTime0:ignTime1 = ignRelTime0:ignRelTime1 + casRiseTime0                             

            ;-----------------------------------------------------------
            ; Based on ignition timing, check if we are going to schedule
            ; ignition at this time or wait for the cas falling edge???
            ;-----------------------------------------------------------
            ldx     timCas0                 ; x = timCas0:timCas1                             
            cpx     #$00ca                  ; (71deg, 4deg BTDC)                              
            bcs     L1701                   ; Branch if timCas0:timCas1 < $00ca (71deg, 4deg BTDC)                            
            brset   casFlags0, #$40, L1700  ; Branch if timing adjustment mode is active                                
            brset   casFlags0, #$10, L1701  ; Branch if rpm(Tcas) >  1540rpm

            ;--------------------------------------------------------------
            ; timCas0:timCas1 >= $00ca (71deg, 4deg BTDC)  
            ; and  timing adjustement mode is active or rpm(Tcas)<=1540rpm
            ;
            ; Set flag and wait for the cas falling edge
            ;--------------------------------------------------------------
L1700       orm     ignFallFlags, #$01      ; Set flag indicating we need to schedule ignition on the cas falling edge                               
            bra     L1703                   ; Branch to continue                             

            ;---------------------------------------------------------------------
            ; At this point, enerFlags=1 if coil is energized or enerFlags=2
            ; if energization has been scheduled. In the case where enerFlags=2
            ; ignition will be scheduled in the output compare subroutine, i.e.
            ; coilFunc, we therefore don't need to schedule it here. In the case
            ; where enerFlags=1, we will now schedule ignition...
            ;---------------------------------------------------------------------
L1701       ldaa    enerFlags               ; a = enerFlags                             
            cmpa    #$02                    ;                             
            beq     L1703                   ; Branch if enerFlags=2

            ;------------------------------------------------------------
            ; enerFlags=1, we will now schedule ignition
            ; Make sure ignition time is sufficiently in 
            ; the future to be valid. If not, use ignition time of "now"
            ;------------------------------------------------------------
            ldd     t3_clock1               ; d = t3_clock1                                    
            addd    #$0006                  ; d = t3_clock1 + $0006 (24usec)                             
            xgdx                            ; x = t3_clock1 + $0006                            
            cpx     ignTime0                ;                              
            bpl     L1702                   ; Branch to use t3_clock1 + $0006 if ignTime0 is "in the past"
            ldx     ignTime0                ; ignTime0 is valid, use it

            ;--------------------------------------------------------
            ; Schedule coil ignition time, set the proper coil bits
            ; and update ignTime0 with the interrupt time used
            ;--------------------------------------------------------
L1702       stx     t3_outCmpWr             ; Schedule interrupt time on first output compare register  
            ldaa    t3_csr1                 ; Go to next output compare register                                                           
            stx     t3_outCmpWr             ; Schedule interrupt time on second output compare register                                    
            orm     t3_csr0, #$0c           ; Set both coil bits in t3_csr0, i.e. provoke ignition at scheduled time
            stx     ignTime0                ; Store actual value used                             

            ;---------------------------------------------------------------------------------------
            ; Common branching point for all code above (except re-init)
            ;
            ; Update enerAbsTimeNext0, The absolute coil energization time for the next cylinder???
            ;---------------------------------------------------------------------------------------
L1703       ldd     TcasNew0                ; d = TcasNew0:TcasNew1                              
            subd    enerLenX0               ; d = TcasNew0 - enerLenX0                             
            addd    ignRelTime0             ; d = TcasNew0 - enerLenX0 + ignRelTime0                            
            addd    casRiseTime0            ; d = TcasNew0 - enerLenX0 + ignRelTime0 + casRiseTime0                                        
            std     enerAbsTimeNext0        ; enerAbsTimeNext0 = casRiseTime0 + TcasNew0 - enerLenX0 + ignRelTime0

            ;------------------------------------------------------------------
            ; Check enerAbsTimeNext0 to make sure it is not too close
            ; to the current cylinder ignition time (1ms min between the two)
            ;------------------------------------------------------------------
            ldd     ignTime0                 ; d = ignTime0                             
            addd    #$00fa                   ; d = ignTime0 + $fa (1ms)                              
            cmpd1   enerAbsTimeNext0         ;                              
            bmi     L1704                    ; Branch if ignTime0 + $fa < enerAbsTimeNext0, energization time of next cylinder is far enough                              
            std     enerAbsTimeNext0         ; Energization of next cylinder is to close to ignition of current cylinder, use closest possible value, enerAbsTimeNext0 = ignTime0 + $fa                              

            ;----------------------------------------------------------------------------
            ; Section to update ignFallRelTime0, the ignition time relative to the cas falling edge
            ; It will be non zero only if it makes sense to schedule ignition on the falling edge
            ; i.e. timing >= 5degBTDC or timing adjustment mode is active, etc...
            ;----------------------------------------------------------------------------
L1704       clra                            ; a = 0                            
            clrb                            ; b = 0                            
            std     ignFallRelTime0         ; ignFallRelTime0 = 0, in case we don't update it below                              
            ldd     timCas0                 ; d = timCas0                              
            subd    #$00c7                  ; d = timCas0 - $00c7                              
            bls     L1708                   ; Branch to use  ignFallRelTime0=0 if timCas0 <= $00c7 (70deg, 5deg BTDC)
            brclr   casFlags0, #$40, L1705  ; Branch to compute ignFallRelTime0 if timing adjustment mode is not active                               
            ldd     #$0032                  ; timing adjustment mode is active, use default of d = $0032 (ignFallRelTime0 = 200us, almost on the CAS falling edge, i.e. 5degBTDC)                              
            bra     L1707                   ; Branch to update ignFallRelTime0 
                                         
            ;---------------------------------------------------------------------------------------------
            ; Compute 
            ;     [ignFallRelTime0:ignFallRelTime1] = [TcasNew0:TcasNew1]/2 * (timCas0 - $00c7)/256 - $12 
            ;                                       = [TcasNew0:TcasNew1]/2 * (timCas0 - 70deg)/256 - $12 
            ;
            ; [ignFallRelTime0:ignFallRelTime1] is the ignition time (timer clock) 
            ; relative to the CAS falling edge (-5 deg BTDC) minus 72us 
            ;
            ; Imposed minimum value is 1 since ignFallRelTime0=0 indicate we should not use it...
            ;---------------------------------------------------------------------------------------------
L1705       stab    temp24                  ; temp24 =  timCas0 - $00c7                              
            ldaa    TcasNew1                ; a = TcasNew1                              
            mul                             ; d = TcasNew1 * (timCas0 - $00c7)                            
            ldab    temp24                  ; b = timCas0 - $00c7                              
            staa    temp24                  ; temp24 = TcasNew1/256 * (timCas0 - $00c7)                              
            ldaa    TcasNew0                ; a = TcasNew0                             
            mul                             ; d = TcasNew0 * (timCas0 - $00c7)                            
            addb    temp24                  ; d = TcasNew0 * (timCas0 - $00c7) + TcasNew1/256 * (timCas0 - $00c7) =  (timCas0 - $00c7) * (TcasNew0 + TcasNew1/256) = (timCas0 - $00c7)/256 * [TcasNew0:TcasNew1]                              
            adca    #$00                    ; propagate carry                            
            lsrd                            ; d = (timCas0 - $00c7)/256/2 * [TcasNew0:TcasNew1]                             
            subd    #$0012                  ; d = (timCas0 - $00c7)/256/2 * [TcasNew0:TcasNew1] - $12                              
            bcs     L1706                   ; Branch if underflow                             
            bne     L1707                   ; Branch if not null                             
L1706       ldd     #$0001                  ; Null or underflow, use min of $0001                              
L1707       std     ignFallRelTime0         ; ignFallRelTime0 = [TcasNew0:TcasNew1]/2 * (timCas0 - $00c7)/256 - $12
L1708       bra     L1713                   ; Branch to normal code continuation
                               
            ;--------------------------------------------------------------
            ; Section to re-init timing stuff in case of detected problems
            ; 2 different entry points, L1709 and L1710
            ;--------------------------------------------------------------
            ;----------------
            ; Update TcasLast0
            ;----------------
L1709       ldx     temp22                  ; get Tcas                                           
            stx     TcasLast0               ; store Tcas in TcasLast0                                

            ;---------------------------------------------------------
            ; Init casFlags0 to 0 or 1 depending where we came from
            ;---------------------------------------------------------
            clra                            ; a = 1, rpm(Tcas)<505, no timing adjustment mode, etc                             
            bra     L1711                   ;                              
L1710       ldaa    #$01                    ; a = 1, rpm(Tcas)>=505, no timing adjustment mode, etc.                            
L1711       staa    casFlags0               ; casFlags0 = 0 or 1                              

            ;-------------------------------------------
            ; Flush both coil output compare registers,
            ; i.e. write the fartest possible time
            ;-------------------------------------------
            ldx     t3_clock1               ;                                    
            dex                             ; x = t3_clock1-1, the fartest possible time                             
            stx     t3_outCmpWr             ; Flush first output compare register                                       
            ldaa    t3_csr1                 ; Go to next output compare register                                                             
            stx     t3_outCmpWr             ; Flush second output compare register                                      

            ;----------------------------------
            ; Reset the current coil bit to 0?
            ;----------------------------------
            ldaa    tdcMask0                ; a = $02 or $04
            asla                            ; a = $04 or $08                                          
            coma                            ; complement, a=~($04 or $08)
            anda    t3_csr0                 ; Reset the coil bit to 0, energize coil at next interrupt
            staa    t3_csr0                 ; Update t3_csr0                              

            ;--------------------------------------------
            ; Re-init control register/flush them??? 
            ; Not sure what this means???
            ;--------------------------------------------
            ldaa    #$09                    ; a = $09                            
            brset   tdcMask0, #$02, L1712   ; branch if tdcMask0 is $02 (current TDC is for cylinder 1 or 4)                              
            ldaa    #$06                    ; a = $06, current TDC is for 2 or 3                           
L1712       staa    t3_csr1                 ; t3_csr1 = $06 or $09 (00000110 or 00001001)                                   
            clra                            ; a = 0                            
            staa    t3_csr1                 ; t3_csr1 = 0                                   

            ;--------------------------
            ; Re-init timing variables
            ;--------------------------
            ldd     TcasLast0               ; d = TcasLast0                                
            std     TcasNew0                ; TcasNew0:TcasNew1 = TcasLast0                                 
            clra                            ;                             
            clrb                            ; d = 0                             
            std     ignFallRelTime0         ; ignFallRelTime0 = 0                             
            ldx     #$00ca                  ; 4deg BTDC                              
            stx     timCas0                 ; timCas0 = 4deg BTDC                                
            staa    enerFlags               ; enerFlags = 0
            ldaa    #$a0                    ; 4.75deg BTDC                             
            staa    tim61                   ; tim61 = 4.75deg BTDC     
                                     
            ;-----------------------
            ; Normal flow continues
            ;-----------------------
            ;--------------------------------------------
            ; Update TcasLast128 = TcasLast0/128
            ;--------------------------------------------
L1713       ldd     TcasLast0               ; d = TcasLast0                                
            asld                            ; d = 2 * TcasLast0                            
            bcc     L1714                   ; Branch if no overflow                              
            ldaa    #$ff                    ; use max of $ff                            
L1714       staa    TcasLast128             ; TcasLast128 =  2 * TcasLast0/256 = TcasLast0/128
                             
            ;---------------------------------------
            ; Re-init t3_csr0 and t1_csr mode bits
            ; This also changes the cas edge detection 
            ; polarity for the next interrupt
            ;---------------------------------------
            ldaa    t3_csr0                 ; a = t3_csr0                             
            anda    #$0c                    ; Reset 1111 0011, reset all except bits corresponding to coil output
            oraa    #$52                    ; Set 0101 0010, set normal control bits...                            
            ldab    t1_csr                  ; b = t1_csr                               
            andb    #$19                    ; reset 1110 0110                            
            orab    #$02                    ; set 0000 0010, cas edge detection polarity                            
            ldx     t1_inCapt               ; x = t1_inCapt (clear input capture flag?)                               
            staa    t3_csr0                 ; t3_csr0  = t3_csr0  & 0000 1100 | 0101 0010                             
            stab    t1_csr                  ; t1_csr = t1_csr & 0001 1001 | 0000 0010                                

            ;--------------------------------------
            ; Re-init timer T40s_casInt to 1.275sec
            ;--------------------------------------
            ldaa    #$33                    ; 1.275sec 
            staa    T40s_casInt             ; T40s_casInt = 1.275sec                                  

            ;----------------------
            ; Update TcasOld
            ;----------------------
            ldd     Tcas                    ; d = Tcas                            
            std     TcasOld                 ; TcasOld = Tcas                               

            ;---------------------------------------------------
            ; Compute new Tcas = 1/2 * [TcasLast0:TcasLast1]
            ; and limit max value to $7fff (min rpm of 229rpm)
            ;---------------------------------------------------
            ldd     TcasLast0               ; d = TcasLast0
            lsrd                            ; d = TcasLast0/2                            
            cmpa    #$80                    ;                             
            bcs     L1715                   ; Branch if TcasLast0/2/256 < $80, i.e. TcasLast0/2 < $7fff?
            ldd     #$7fff                  ; Use max of $7fff (229rpm)                              
L1715       std     Tcas                    ; store new Tcas for rpm calculation

            ;----------------------------------------------------------
            ; Update coilHist with input from the coil sensing circuit
            ; coilHist basically contains the sensing circuit value 
            ; (0 or 1) for the last 8 interrupts, bit 7 being the 
            ; oldest and  bit 0 the newest
            ;----------------------------------------------------------
            ldaa    coilHist                ; a = coilHist                             
            asla                            ; a = 2*coilHist (shift existing bits left)                            
            brclr   p4Latched, #$04, L1716  ; Branch if CAS "clock" is clear?
            inca                            ; a = 2*coilHist + 1 (set lower bit)
L1716       staa    coilHist                ; coilHist = updated CAS clock history

            ;-------------------------------------------------------------
            ; If "engine is running and rpm<5000 and 8V<=battRaw<=18V"
            ; then check if coilHist lower 4 bits make sense, i.e. should
            ; have changed on every CAS interrupt since we have ignition
            ; just as often...
            ;-------------------------------------------------------------
            ldab    #$20                      ; preload b = $20 for eventual storage in coilChkCnt
            brclr   coilChkFlags, #$20, L1722 ; Bail if not "engine is running and rpm<5000 and 8V<=battRaw<=18V" (we don't perform the test, so reset timer as if no problem...)
            anda    #$0f                      ; a = coilHist & $0f                              
            cmpa    #$05                      ;                             
            beq     L1717                     ; Branch if coilHist & $0f = $05  (0000 0101)                            
            cmpa    #$0a                      ;                              
            bne     L1718                     ; Branch if coilHist & $0f != $0a  (0000 1010)                            

            ;------------------------------------------------------------------
            ; coilHist & $0f = $05 or $0a (0101 or 1010), this is the normal
            ; alternating pattern of the check circuit, everything is therefore OK, 
            ; reset error bit and allow all 4 injectors to be used
            ;------------------------------------------------------------------
L1717       andm    coilChkFlags, #$7f      ; Reset error flag                                
            orm     coilChkFlags, #$0f      ; Set all 4 lower bits to 1, meaning all 4 injectors can be used
            bra     L1722                   ; Bail                              

            ;---------------------------------------------------------------
            ; coilHist & $0f != $05 or $0a
            ; That means some ignition signal were not properly generated.
            ;
            ; Investigate a little more the bit pattern and then decide
            ; if we need to deactivate some injectors.
            ; Did not attempt to understand this yet???
            ;---------------------------------------------------------------
L1718       lsra                            ; 
            lsra                            ; a = (coilHist & $0f)/4                             
            eora    coilHist                ; a = (coilHist & $0f)/4 eor coilHist                            
            lsra                            ; shift lower bit in carry                             
            bcc     L1722                   ; Branch if lower bit 0, no error to flag yet??                           
            ldaa    coilHist                ; a = coilHist                             
            lsra                            ; a = coilHist/2                            
            eora    coilHist                ; a = coilHist/2 eor coilHist                             
            lsra                            ; shift lower bit in carry                            
            bcs     L1720                   ; Branch if lower bit 1, flag an error but dont deactivate injectors                             

            ;--------------------------------------------------------------------------------
            ; Select injectors that are OK to use depending on whether TDC is active or not
            ;--------------------------------------------------------------------------------
            ldab    #$05                   ; Set bits corresponding to injectors 1 and 4                              
            brclr   port3, #$04, L1719     ; Branch if TDC signal is active
            ldab    #$0a                   ; Set bits corresponding to injectors 3 and 2                              

            ;------------------------------------------------------------
            ; Update coilChkFlags with injectors that are ok to use
            ;------------------------------------------------------------
L1719       ldaa    coilChkFlags            ; a = coilChkFlags                              
            anda    #$f0                    ; reset 4 lower bits
            aba                             ; Set the injectors that are OK to use in lower 4 bits
            staa    coilChkFlags            ; Update coilChkFlags    
                                     
            ;---------------------------------------------------------
            ; We have a missing ignition signal, decrement coilChkCnt 
            ; (min of 0) and set coilChkFlags.7 error flag if it reached 0
            ; That would mean we missed $20 ignition signals...
            ;---------------------------------------------------------
L1720       ldab    coilChkCnt              ; b = coilChkCnt                              
            beq     L1721                   ; Branch if coilChkCnt=0                             
            decb                            ;                             
            bra     L1722                   ;
L1721       orm     coilChkFlags, #$80      ; Set error flag

            ;---------------------------------------------------
            ; Store new coilChkCnt value, $20 loaded way above 
            ; or decremented value just calculated
            ;---------------------------------------------------
L1722       stab    coilChkCnt              ;                                                                                                     

            ;----------------------------------------------------
            ; Section to update knockSum from the knock sensor
            ;----------------------------------------------------
            ;-----------------------------------------------
            ; Skip section (use knockSum = 0 ) if car has been 
            ; running less than 1 sec
            ;-----------------------------------------------
            brclr   knockFlags, #$40, L1731 ; Branch to use knockSum = 0 if engine has been running less than 1 sec?

            ;---------------------------------------
            ; b = rawKnock value from the ADC port
            ;---------------------------------------
            ldaa    #$0e                    ; A = knock port number 6 with start bit set = $06 | $08                                                                                
            jsr     readAdc2                ; b = rawKnock from adc port

            ;-----------------------------------------
            ; Increment knockTimer up to max of 255
            ;-----------------------------------------
            ldaa    knockTimer              ; Read current counter value                                                                          
            inca                            ; increment some knock related counter                                                               
            bne     L1723                   ; Branch if no overflow
            ldaa    #$ff                    ; overflow, use max
L1723       staa    knockTimer              ; store new counter value                                                              

            ;--------------------------------------------------
            ; Decide if we are going to use rawKnock directly
            ;--------------------------------------------------
            cmpb    #$0c                    ; 
            bcs     L1725                   ; branch to use it if rawKnock < $0c                                                                                     
            cmpb    #$24                    ; 
            bhi     L1725                   ; branch to use it if rawKnock > $24

            ;----------------------------------------------------------------
            ; $0c <= rawKnock <= $24, this is a zone where we don't count
            ; rawKnock except if  knockTimer > $78. knockTimer is however 
            ; reset to 0 which means it only applies to the first time 
            ; that happens. Basically, we ignore rawKnock when it is 
            ; between $0c and $24???
            ;----------------------------------------------------------------
            cmpa    #$78                    ;                                                                                     
            bhi     L1724                   ; Branch if knockTimer > $78 

            ;--------------------------------------------
            ; $0c <= rawKnock <= $24 and knockTimer<78
            ;
            ; Use rawKnock=0 and reset knockTimer
            ;--------------------------------------------
            clrb                            ; b = 0                                                                                    
L1724       clr     knockTimer              ; reset knockTimer                                                                                     

            ;----------------------------------
            ; Update knockSensor from rawKnock
            ;----------------------------------
L1725       stab    knockSensor             ; knockSensor = rawKnock (processed port value)                                                      

            ;----------------------------------
            ; Compute a = (rawKnock-4)/8
            ;----------------------------------
            ldaa    knockSensor             ; a = rawKnock
            suba    #$04                    ; rawKnock -= 4                                                         
            bcc     L1726                   ; Branch rawKnock-4 >= 0
            clra                            ; Use min of 0    
L1726       lsra                            ;                                                                                     
            lsra                            ;                                                                                     
            lsra                            ; a = (rawKnock-4)/8                                                           

            ;------------------------------------------------- 
            ; Compute a = (rawKnock-4)/8/2 if under low load
            ;------------------------------------------------- 
            brset   knockFlags, #$80, L1727 ; branch if airVol>$49  (high load)
            lsra                            ; knock = knock/2 under low load                                                      
            bra     L1728                   ;                                                                                      

            ;------------------------------------------------- 
            ; Check for max value of 7 under high load?
            ;------------------------------------------------- 
L1727       cmpa    #$07                    ;                                                                                                 
            bcs     L1728                   ; branch if (rawKnock-4)/8 < 7                                                                              
            ldaa    #$07                    ; Use max of 7                                                                         

            ;-----------------------------------------------------------
            ; Add min((rawKnock-4)/8,7) or (rawKnock-4)/8/2 to knockSum
            ; and check for max of 43
            ;-----------------------------------------------------------
L1728       adda    knockSum                ; a = knockSum + min((rawKnock-4)/8,7) or (rawKnock-4)/8/2
            bcs     L1729                   ; Branch if overflow                                                                                                 
            cmpa    #$2b                    ; No overflow, check for max of 43
            bls     L1730                   ; Branch if new knockSum <=43                                                                         
L1729       ldaa    #$2b                    ; Use max of 43 
                                                                                               
            ;-------------------------------------------------------
            ; If knock sensor not working, use knockSum=$09 under 
            ; high load and knockSum=$00 under low load
            ;-------------------------------------------------------
L1730       brclr   state2, #$20, L1732     ; Branch if knock sensor working properly?                                                                                                   
            ldaa    #$09                    ; a = $09                                                                                                
            brset   knockFlags, #$80, L1732 ; Branch if airVol>$49                                                                                                  
L1731       clra                            ;                                                                                                 

            ;-------------------------------------------------------------
            ; Store new knockSum and reset knock sensor physical filter
            ;-------------------------------------------------------------
L1732       staa    knockSum                ; Store new knock sum                                                                                 
            orm     port6, #$01             ; Reset knock sensor physical filter?


            ;----------------------------------------------
            ; Update maxAdv for E931 in order to slowly
            ; remove its effect with time
            ;----------------------------------------------
#ifdef E931
            ldaa    T_maxAdv                ;                               
            beq     Mf078                   ; Branch if timer T_maxAdv expired                              
            deca                            ; Decrement timer                             
            bne     Mf081                   ; Bail if not expired                              

            ;---------------------------------------------------------
            ; Timer expired increase maxAdv by 1 (increase 
            ; timing advance limit up to $80) and restart timer to 1
            ;---------------------------------------------------------
Mf078       ldab    maxAdv                  ;                               
            bmi     Mf081                   ; Branch if maxAdv>=$80 (no limit to advance)                                
            inc     maxAdv                  ;                               
            ldaa    #$01                    ; re-init timer t0 1 (we do it every loop)                              
Mf081       staa    T_maxAdv                ;                               
#endif

            ;------------------------------------------
            ; Set flag masCasFlags.1 indicating to the 
            ; main loop that it can update rpmX4Filt
            ;------------------------------------------
            orm     masCasFlags, #$01       ;                                

            ;---------------------------------------------------------------------
            ; Section to update o2Fbk from o2 sensor during closed loop operation
            ;---------------------------------------------------------------------
            brclr   state1, #$80, L1735     ; Bail  if open loop mode                                
            clra                            ; a = 0                            
            ldab    o2Raw                   ; b = o2Raw
            cmpb    #$1a                    ;                                                     
            bcc     L1733                   ; branch if o2Raw >= 0.507V                                 

            ;-----------------------------------------
            ; o2Raw < 0.507V (lean) 
            ; increase o2Fbk = o2Fbk + 8 * o2Fbk_inc
            ;-----------------------------------------
            ldab    o2Fbk_inc               ; d = o2Fbk_inc (a cleared earlier)                             
            asld                            ;                             
            asld                            ; d = 8 * o2Fbk_inc                             
            addd    o2Fbk                   ; d = 8 * o2Fbk_inc + o2Fbk
            bcc     L1734                   ; Branch if no overflow                             
            ldd     #$ffff                  ; Use max of $ffff                              
            bra     L1734                   ; Branch to store

            ;-------------------------------------
            ; o2Raw >= 0.507V (rich) 
            ; decrease o2Fbk = o2Fbk - 4 * o2Fbk_dec
            ;-------------------------------------
L1733       ldab    o2Fbk_dec               ; d = o2Fbk_dec (a cleared earlier)                              
            asld                            ;                             
            asld                            ; d = 4 * o2Fbk_inc                            
            std     temp8                   ;                               
            ldd     o2Fbk                   ;                              
            subd    temp8                   ; d = o2Fbk - 4 * o2Fbk_dec                               
            bcc     L1734                   ; Branch if no underflow                             
            clra                            ;                             
            clrb                            ; Underflow, use min of $0000                            

            ;--------------
            ; Update o2Fbk 
            ;--------------
L1734       std     o2Fbk                   ; Store new o2Fbk

            ;-------------------------------------
            ; Return from interrupt
            ;-------------------------------------
L1735       rti                             ;                             



;******************************************************************
;
;
; Section processing the CAS interrupt on the falling edge
;
;
;******************************************************************
            ;------------------------------------------------------------
            ; Check which of t3_clock1 or t3_clock2 should be used?
            ; Not sure what that bit means???????????
            ;------------------------------------------------------------
casFallProc brset   t3_csr0, #$10, L1737    ; Branch if we should use t3_clock2, nothing to do, that's what we assumed above (from where we jumped to casFallProc...)

            ;-------------------------------------------------------------------------
            ; t3_clock1 should be used, our assumption that it was
            ; t3_clock2 was wrong, update d and  temp20 with the correct values
            ;-------------------------------------------------------------------------
            xgdx                            ; d = t3_clock1
            std     temp20                  ; temp20 = t3_clock1
                                                          
            ;------------------------------------------------
            ; Branch to rest of code if the time between CAS
            ; interrupts makes sense (rpm is not too high...)
            ;
            ; The time measured here is the cas pulse width 
            ; since it is measured from rising to falling edge
            ; Since the cas pulse is 70deg then the 0.5ms below
            ; correspond to 360/70*0.5ms = 2.57ms per rotation which
            ; correspond to 23333rpm???
            ;------------------------------------------------
L1737       subd    casRiseTime0            ; d = (t3_clock1 or t3_clock2) - casRiseTime0
            cmpd    #$007d                  ; 0.5ms at 250KHz                               
            bcc     L1738                   ; Branch if (t3_clock1 or  t3_clock2 - casRiseTime0) >= $007d

            ;------------------------------------------------
            ; RPM seems too high to make sense, check if it is
            ; not instead because RPM is so low that the 16 bit 
            ; counter subtraction above rolled-over.
            ;
            ; Branch to rest of code if the T200_casRise timer shows
            ; that rpm is very low... 
            ;------------------------------------------------
            ldaa    T200_casRise                                                 
            cmpa    #$0e                    ; 70ms at 200Hz                             
            bcs     L1738                   ; branch if T200_casRise<70ms, T200_casRise is init with 265ms, the time between interrupt is very high                                                                                                                            

            ;-------------------------------------------------------------
            ; Time between interrupts doesn't make sense, just ignore it
            ; return from interrupt
            ;-------------------------------------------------------------
            rti                                                          

            ;---------------------------------------------------------------
            ; Update temp22:temp23 = Tcas measured on the cas falling edge
            ;---------------------------------------------------------------
L1738       ldd     temp20                  ; d = temp20
            subd    casFallTime0            ; d = temp20-casFallTime0(old counter) = Tcas = 250000/2/(rpm/60)                                      
            std     temp22                  ; temp22:temp23 = Tcas (temp22 is not dedicated for that purpose...)                                 

            ;---------------------------------
            ; Validate temp22:temp23 = Tcas
            ;---------------------------------
            ldab    T200_casFall            ;                               
            beq     L1739                   ; Branch if timer expired (very long Tcas...)                             
            tsta                            ;                             
            bmi     L1740                   ; Bail if Tcas/256 >= 128 (rpm<229)                              
            cmpb    #$0e                    ;                             
            bhi     L1740                   ; Branch if T200_casRise > $0e (70ms)                             
L1739       ldd     #$ffff                  ; Use max Tcas                               
            std     temp22                  ; store Tcas
                              
            ;--------------------------------------------------------------------
            ; At this point, we will check the CAS signal to make sure it stays
            ; reset until 56us after the start of the interrupt. I guess this might
            ; be to filter eventual glitches in the CAS signal
            ;--------------------------------------------------------------------
L1740       ldd     temp20                  ;                                    
            addd    #$000e                  ; d = StartInterruptTime + $0e (56us)                               
L1741       brset   port5, #$01, L1742      ; Branch as long as CAS bit is set (CAS signal is reset)
            rti                             ; CAS bit was reset, Bail of interrupt
L1742       cmpd1   t3_clock1               ; Compare current time to time stored when we started the interrupt processing                                 
            bpl     L1741                   ; Loop if t3_clock1 < (temp20 + $0e (56us)), i.e. if its been less than 56us since interrupt was called




;******************************************************************
;
;
; Interrupt was valid
; Proceed with processing stuff on the CAS falling edge
;
;
;******************************************************************
            ;---------------------------------------------------------
            ; restart T200_casRise timer to 175ms
            ;---------------------------------------------------------
            ldaa    #$35                    ; 265ms                             
            staa    T200_casFall            ; T200_casFall = 265ms                               

            ;-----------------------
            ; Update casFallTime0 
            ;-----------------------
            ldd     temp20                  ;                                     
            std     casFallTime0            ; casFallTime0 = temp20                             

            ;---------------------------------------------------------------------
            ; Branch to re-init if T40s_casInt expired or if Tcas/256 >= $80
            ;
            ; i.e. no cas rising edge interrupt received 
            ; in the last 1.275sec or rpm is very low
            ;---------------------------------------------------------------------
            brclr   T40s_casInt, #$ff, L1743 ; Branch if T40s_casInt expired                                    
            ldaa    temp22                   ; a = Tcas/256                             
            bpl     L1744                    ; Branch if a < $80                             

            ;---------------------------------------------------------
            ; T40s_casInt expired or Tcas/256 >= $80 (too big)
            ; Re-init casFlags0, enerFlags and control registers 
            ; and jump over the entire ignition section
            ;---------------------------------------------------------
L1743       clra                            ; a = 0                            
            staa    casFlags0               ; casFlags0 = 0                             
            staa    enerFlags               ; enerFlags = 0                              
            orm     t3_csr0, #$0c           ; set 0000 1100, disable both coils                               
            orm     t3_csr1, #$0a           ; set 0000 1010, ???                                     
            andm    t3_csr1, #$f0           ; reset 0000 1111 (reset the bit we just set...)                                     
            jmp     L1765                   ; Bail, jump over ignition section                             
                                            
            ;---------------------------------------------------------
            ; Section to process ignFallRelTime0 when it is non-null
            ; Firs check just that...
            ;---------------------------------------------------------
L1744       ldd     ignFallRelTime0         ; d = ignFallRelTime0:ignFallRelTime1                              
            bne     L1745                   ; Branch if ignFallRelTime0:ignFallRelTime1 != 0                             
            jmp     L1754                   ; Bail since ignFallRelTime0=0

            ;----------------------------------------------------------
            ; At this point ignFallRelTime0 != 0
            ; When ignFallRelTime0:ignFallRelTime1 is not  0, it 
            ; means we determined on the cas rising edge that ignition
            ; would be scheduled on the cas falling edge, which we are in
            ; now... But coil need to be energized first...
            ;
            ; Check if current coil is already energized
            ;----------------------------------------------------------
L1745       ldaa    port5                   ; a = port5                             
            anda    tdcMask0                ; a = port5 & tdcMask0  ($02 or $04)                            
            beq     L1750                   ; Branch if coil is energized

            ;---------------------------------------------
            ; Currrent coil is not yet energized
            ;---------------------------------------------
            ;----------------------------------------------------------------------------
            ; Check if energization has been scheduled?, this would mean energization
            ; will occur soon, or should have occured by now
            ;----------------------------------------------------------------------------
            brset   enerFlags, #$02, L1746  ; Branch if enerFlags=2, energization was scheduled
            jmp     L1754                   ; Bail, not sure what this would mean, probably that ignition already occured and there is nothing left to do??????

            ;--------------------------------------------------------------
            ; At this point 
            ; -Coil is not yet energized 
            ; -We determined on the cas rising edge that ignition would be
            ;  schedule on the cas falling edge (thats now...)
            ; -enerFlags indicates energization was scheduled from 
            ;  the cas rising edge and should already have occured 
            ;  or will occur very soon??? Just reschedule energization...
            ;--------------------------------------------------------------
            ;----------------------------------------------------------------------------------
            ; Compute enerAbsTime0:
            ;
            ;    enerAbsTime0 = casFallTime0 + ignFallRelTime0 - enerLenX0 - TcasLast128
            ;
            ; enerAbsTime0 is the coil energization absolute time (timer clock) 
            ; (calculated from the CAS falling edge in this case)
            ;----------------------------------------------------------------------------------
L1746       ldd     ignFallRelTime0       ; d = ignFallRelTime0                             
            subd    enerLenX0             ; d = ignFallRelTime0 - enerLenX0                             
            subb    TcasLast128           ; d = ignFallRelTime0 - enerLenX0 - TcasLast128                             
            sbca    #$00                  ; propagate carry                             
            addd    casFallTime0          ; d = ignFallRelTime0 - enerLenX0 - TcasLast128 + casFallTime0                              
            std     enerAbsTime0          ; enerAbsTime0 = casFallTime0 + ignFallRelTime0 - enerLenX0 - TcasLast128

            ;---------------------------------------------------------------------------
            ; Reset the proper coil bit in t3_csr0, i.e. energize coil at next interrupt
            ;---------------------------------------------------------------------------
            ldaa    tdcMask0                ; a = $02 or $04                             
            asla                            ; a = $04 or $08
            coma                            ; a = ~($04 or $08)                            
            anda    t3_csr0                 ; Reset that coil bit, i.e. have the coil energized the next time
            staa    t3_csr0                 ; Update t3_csr0                              

            ;------------------------------------------------------------------------------
            ; Check if enerAbsTime0 that we just calculated is sufficiently in the future
            ;------------------------------------------------------------------------------
            ldd     t3_clock1               ; d = t3_clock1                                   
            addd    #$0006                  ; d = t3_clock1 + $06 (24us)                             
            xgdx                            ; x = t3_clock1 + $06                            
            cpx     enerAbsTime0            ;                              
            bmi     L1747                   ; Branch to use enerAbsTime0 if it is sufficiently "in the future", i.e. t3_clock1 + $06 < enerAbsTime0

            ;------------------------------------------------------------------------
            ; enerAbsTime0 is not sufficiently in the future, 
            ;
            ; schedule energization for "now", i.e. t3_clock1 + $06 
            ; this is 24usec (a few cycles) I assume the output compare will
            ; therefore happen before we schedule the ignition later in the code 
            ; below... Note that only the first output compare register is updated.
            ; Also update enerAbsTime0
            ;
            ; Update enerFlags = 1 to reflect the fact that coil is now energized.
            ; It is not really but it will be in 24usec....
            ;------------------------------------------------------------------------
            stx     enerAbsTime0            ; enerAbsTime0 = t3_clock1 + $06
            stx     t3_outCmpWr             ; Schedule energization interrupt time on first output compare register                                   
            ldaa    #$01                    ;                             
            staa    enerFlags               ; Make sure flag reflects the fact that coil is energized or will be very soon???                             
            bra     L1752                   ; Branch to compute ignition time                             

            ;-----------------------------------------------------
            ; enerAbsTime0 is sufficiently in the future
            ; Schedule regular coil energization interrupt time 
            ; and update enerAbsTime0 with it.
            ;
            ; Note that Ignition will be calculated below but scheduled 
            ; only  when the output compare interrupt to energize the 
            ; coil actually happens (i.e. in coilFunc)
            ;-----------------------------------------------------
L1747       ldx     enerAbsTime0            ; x = enerAbsTime0                             
            stx     t3_outCmpWr             ; Schedule interrupt time on first output compare register                                     
            ldaa    t3_csr1                 ; Go to next output compare register                                                           
            stx     t3_outCmpWr             ; Schedule interrupt time on second output compare register 
                                                
            ;---------------------------------------------------------------------------
            ; Branch to compute ignTime0
            ; if we predicted we would schedule ignition on the CAS falling edge???
            ;---------------------------------------------------------------------------
            brset   ignFallFlags, #$01, L1749 ; Branch if ignFallFlags = 1

            ;-------------------------------------------------------------------
            ; Flag is not set, do it anyway if 
            ;
            ;     abs(ignTime0 - casFallTime0 - ignFallRelTime0) >= TcasLast128
            ;           abs(compIgnFallRelTime - ignFallRelTime0) >= TcasLast128
            ;
            ; where compIgnFallRelTime = ignTime0 - casFallTime0 is the ignition
            ; time relative to the cas falling edge but calculated from ignTime0...
            ;
            ; i.e. Do it anyway if they are more than 1.4deg apart??? Why not
            ; just recompute it anyway instead of doing this lenghty 
            ; computation to check it, there must be a reason??? I guess
            ; in most cases, it might be more acurate to use ignFallRelTime0
            ; but in case it is too far apart from what makes sense at this time
            ; then just use whatever makes sense at this time...
            ;-------------------------------------------------------------------
            ldd     ignTime0                ; d = ignTime0                             
            subd    casFallTime0            ; d = ignTime0 - casFallTime0                             
            subd    ignFallRelTime0         ; d = ignTime0 - casFallTime0 - ignFallRelTime0                            
            bcc     L1748                   ; Branch if no overflow                             
            coma                            ; overflow, compute 2s complement                            
            comb                            ;                             
            addd    #$0001                  ; d = abs(ignTime0 - casFallTime0 - ignFallRelTime0)                             
L1748       tsta                            ;                             
            bne     L1749                   ; Branch if abs(compIgnFallRelTime - ignFallRelTime0)/256 != 0                             
            cmpb    TcasLast128             ; high part is null, check low part                              
            bcs     L1754                   ; Bail if difference is small, i.e. abs(compIgnFallRelTime - ignFallRelTime0) <  TcasLast128
                                         
            ;------------------------------------------------------------------
            ; Compute ignTime0 = ignFallRelTime0 + casFallTime0
            ; The ignition time computed from the cas falling edge
            ;------------------------------------------------------------------
L1749       ldd     ignFallRelTime0         ; d = ignFallRelTime0                               
            addd    casFallTime0            ; d = ignFallRelTime0 + casFallTime0                             
            std     ignTime0                ; ignTime0 = ignFallRelTime0 + casFallTime0                              
            bra     L1754                   ; Bail                             

            ;----------------------------------------------------------------
            ; At this point we detected that coil is already energized...
            ; Section of code similar to above one...
            ;----------------------------------------------------------------
            ;--------------------------------------------------
            ; Check if flag indicate ignition makes sense???
            ;--------------------------------------------------
L1750       brclr   enerFlags, #$03, L1754    ; Bail if flag indicates coil is not energized and energization is not scheduled???

            ;---------------------------------------------------------------------------
            ; Branch to compute ignTime0
            ; if we predicted we would schedule ignition on the CAS falling edge???
            ;---------------------------------------------------------------------------
            brset   ignFallFlags, #$01, L1752 ; Branch if ??? TDC related                              

            ;-------------------------------------------------------------------
            ; Flag is not set, do it anyway if 
            ;
            ;     abs(ignTime0 - casFallTime0 - ignFallRelTime0) >= TcasLast128
            ;           abs(compIgnFallRelTime - ignFallRelTime0) >= TcasLast128
            ;
            ; where compIgnFallRelTime = ignTime0 - casFallTime0 is the ignition
            ; time relative to the cas falling edge but calculated from ignTime0...
            ;
            ; i.e. Do it anyway if they are more than 1.4deg apart??? Why not
            ; just recompute it anyway instead of doing this lenghty 
            ; computation to check it, there must be a reason??? I guess
            ; in most cases, it might be more acurate to use ignFallRelTime0
            ; but in case it is too far apart from what makes sense at this time
            ; then just use whatever makes sense at this time...
            ;-------------------------------------------------------------------
            ldd     ignTime0                  ; d = ignTime0                              
            subd    casFallTime0              ; d = ignTime0 - casFallTime0                             
            subd    ignFallRelTime0           ; d = ignTime0 - casFallTime0 - ignFallRelTime0                              
            bcc     L1751                     ; Branch if no overflow                             
            coma                              ; overflow, compute 2s complement                            
            comb                              ;                             
            addd    #$0001                    ; d = abs(ignTime0 - casFallTime0 - ignFallRelTime0)                              
L1751       tsta                              ;                             
            bne     L1752                     ; Branch if abs(ignTime0 - casFallTime0 - ignFallRelTime0)/256 > 0                             
            cmpb    TcasLast128               ; high part is zero (a = 0), check low part for minimum                              
            bcs     L1754                     ; Branch if difference is small, i.e. abs(ignTime0 - casFallTime0 - ignFallRelTime0) <  TcasLast128

            ;----------------------------------------------------
            ; Compute ignTime0 = ignFallRelTime0 + casFallTime0
            ; The ignition time computed from the cas falling edge
            ;----------------------------------------------------
L1752       ldd     ignFallRelTime0         ; d = ignFallRelTime0                                              
            addd    casFallTime0            ; d = ignFallRelTime0 + casFallTime0                                     
            std     ignTime0                ; ignTime0 = ignFallRelTime0 + casFallTime0 
                                            
            ;-------------------------------------------
            ; Update enerFlags = 1 since at this 
            ; point we know the coil is energized???
            ;-------------------------------------------
            ldaa    #$01                    ; a = $01                            
            staa    enerFlags               ; enerFlags = $01                             

            ;------------------------------------------
            ; Make sure ignition time is in the future
            ;------------------------------------------
            ldd     t3_clock1               ; d = t3_clock1                                   
            addd    #$0009                  ; d = t3_clock1 + $09 (36usec)                             
            xgdx                            ; x = t3_clock1 + $09                             
            cpx     ignTime0                ;                              
            bpl     L1753                   ; Branch to use t3_clock1 + $09 if ignTime0 is "in the past"                             
            ldx     ignTime0                ; ignTime0 is valid, use it                             

            ;-----------------------------------------------------------
            ; Schedule ignition time on both output compare registers
            ; Update the coil bits and save time in ignTime0
            ;-----------------------------------------------------------
L1753       stx     t3_outCmpWr             ; Schedule interrupt time on first output compare register
            orm     t3_csr0, #$0c           ; Set both coil bits for ignition
            ldaa    t3_csr1                 ; Go to next output compare register                                                            
            stx     t3_outCmpWr             ; Schedule interrupt time on second output compare register                                     
            stx     ignTime0                ; ignTime0 = next interrupt time                             

            ;-----------------------------------------------
            ; Common branching place for most code above...
            ;-----------------------------------------------
            ;---------------------------------------------------------
            ; Section to check if ignition should have occured by 
            ; now and schedule it "now" if needed
            ;---------------------------------------------------------
L1754       brclr   casFlags0, #$02, L1755    ; Branch if rpm(Tcas) < 505 previously
            brset   casFlags0, #$40, L1756    ; Branch to continue if timing adjustement mode active                             
            ldd     timCas0                   ; d = timCas0:timCas1                               
            cmpd    #$00c8                    ;                               
            bcc     L1756                     ; Branch if timCas0 >= $c8 (4.7 BTDC)                             
            ldaa    port5                     ; a = port5                               
            anda    tdcMask0                  ; a = port5 & $02 or $04                              
            bne     L1756                     ; Branch if current coil bit is 1, i.e. coil is not energized
            brclr   enerFlags, #$03, L1756    ; Branch to continue if flag indicate coil is not energized and energization is not scheduled
                                          
            ;-----------------------------------------------------------------------------------
            ; At this point, 
            ;     rpm(Tcas) < 505 
            ; or
            ;     current coil is energized
            ;     and timCas0 < $c8 (4.7 BTDC)
            ;     and enerFlags =  1 or 2, coil is energized or energization is scheduled
            ;
            ; In all those cases, ignition should have occured by now???
            ;
            ; Schedule interrupt on first output compare register to provoke 
            ; ignition now, save time in ignTime0 and clear enerFlags
            ;-----------------------------------------------------------------------------------
L1755       orm     t3_csr0, #$0c           ; Set both coil bits for ignition
            ldx     t3_clock1               ; x = t3_clock1                                   
            inx                             ;                             
            inx                             ; x = t3_clock1 + $02                             
            stx     t3_outCmpWr             ; Schedule interrupt time on first output compare register
            stx     ignTime0                ; Update ignTime0 with the ignition time we just used                              
            clra                            ;                             
            staa    enerFlags               ; enerFlags = 0                             

            ;--------------------------------------------------------------
            ; Section to update ignition stuff when rpm(Tcas) < 505???
            ; Probably a dedicated section when engine is cranking???
            ; First check rpm flag...
            ;--------------------------------------------------------------
L1756       brset   casFlags0, #$02, L1757  ; Branch if rpm(Tcas) >= 505 previously
            jmp     L1765                   ; Bail                         
                
            ;---------------------
            ; rpm(Tcas) < 505rpm
            ;---------------------
            ;---------------------------------------------------------
            ; Compute enerLenX0 = min($60/128 * Tcas, 16*enerLen)
            ;                   = min(   0.75 * Tcas, 16*enerLen)
            ;---------------------------------------------------------
L1757       ldaa    enerLen                 ; a = enerLen                              
            clrb                            ; d = enerLen*256                             
            lsrd                            ;                             
            lsrd                            ;                             
            lsrd                            ;                             
            lsrd                            ; d = enerLen*256/16 = 16*enerLen                            
            std     temp20                  ; temp20 = 16*enerLen                                   
L1758       ldaa    temp23                  ; a = temp23  (low part of Tcas)                            
            ldab    #$60                    ; b = $60                             
            mul                             ; d = $60 * temp23                            
            staa    enerLenX0               ; enerLenX0 = $60/256 * temp23                             
            ldaa    temp22                  ; a = temp22                             
            ldab    #$60                    ; b = $60                            
            mul                             ; d = $60 * temp22                            
            addb    enerLenX0               ; d = $60 * temp22 + $60/256 * temp23 = $60/256 * [temp22:temp23]                             
            adca    #$00                    ; propagate carry                            
            asld                            ; d = $60/128 * [temp22:temp23] = $60/128 * Tcas                            
            bcs     L1759                   ; Branch if overflow
            cmpd1   temp20                  ;                                     
            bcs     L1760                   ; Branch if $60/128 * Tcas < 16*enerLen                            
L1759       ldd     temp20                  ; Use max of 16*enerLen                                     
L1760       std     enerLenX0               ; enerLenX0 = min($60/128 * Tcas, 16*enerLen)                    
         
            ;-------------------------------------------------------------------------------------
            ; Compute  temp20 = casFallTime0 + $9c/256 * Tcas + ignRelTime0  - enerLenX0 
            ;                 = casFallTime0 + 110deg + ignRelTime0  - enerLenX0 
            ;
            ; 110deg is the number of degrees between the CAS falling edge and the next
            ; CAS rising edge since CAS starts at -75deg and ends at -5deg, CAS width = 70deg
            ; and then distance from falling edge to next rising edge = 180deg - 70deg = 110deg
            ;
            ; we are therefore calculating the coil energization absolute time for the next
            ; CAS/cylinder from the CAS falling edge of the current CAS/cylinder... 
            ;-------------------------------------------------------------------------------------
            brclr   tdcCasCount, #$fe, L1765 ; Bail if tdcCasCount = 0 or 1                                    
            ldab    temp23                   ; b = temp23 (low part of Tcas)                            
            ldaa    #$9c                     ; a = $9c                            
            mul                              ; d = $9c * temp23                             
            staa    temp21                   ; temp21 = $9c * temp23/256                               
            ldaa    temp22                   ; a = temp22                             
            ldab    #$9c                     ; b = $9c                             
            mul                              ; d =  $9c * temp22                            
            addb    temp21                   ; d = $9c * temp22 + $9c * temp23/256  = $9c/256 * [temp22:temp23]                            
            adca    #$00                     ; propagate carry                            
            addd    ignRelTime0              ; d = $9c/256 * Tcas + ignRelTime0                             
            subd    enerLenX0                ; d = $9c/256 * Tcas + ignRelTime0  - enerLenX0                             
            addd    casFallTime0             ; d = $9c/256 * Tcas + ignRelTime0  - enerLenX0 + casFallTime0                             
            std     temp20                   ; temp20 = $9c/256 * Tcas + ignRelTime0  - enerLenX0 + casFallTime0                                      

            ;----------------------------------------------------------------------
            ; Verify that energization time does not occur too close to ignition
            ; of current cylinder, i.e. energization should not occur sooner than 
            ; 1ms after ignition of preceeding cylinder
            ;----------------------------------------------------------------------
            ldd     ignTime0                 ; d = ignTime0                              
            addd    #$00fa                   ; d = ignTime0 + $fa (1ms)                              
            cmpd1   temp20                   ;                                    
            bmi     L1761                    ; Branch if ignTime0 + $fa < casFallTime0 + $9c/256 * Tcas + ignRelTime0  - enerLenX0
            std     temp20                   ; Use closest possible energization time of ignTime0 + $fa (1ms)

            ;-------------------------------------
            ; Check if current coil is energized
            ;-------------------------------------
L1761       ldaa    port5                   ; a = port5                              
            anda    tdcMask0                ; a = port5 & tdcMask0 ($02 or $04)                             
            beq     L1763                   ; Branch if coil bit is 0, i.e. coil is energized                              

            ;--------------------------------------------------
            ; Current coil is not yet energized,
            ;
            ; Check that energization time computed above and 
            ; stored in temp20 is sufficiently in the future
            ;--------------------------------------------------
            brset   enerFlags, #$02, L1764  ; Bail if flag indicates coil is energized or energization is scheduled
            ldd     t3_clock1               ; d = t3_clock1                                   
            addd    #$000a                  ; d = t3_clock1 + $0a  (40usec)                            
            xgdx                            ; x = t3_clock1 + $0a                             
            cpx     temp20                  ; Compare to energization time                                    
            bpl     L1762                   ; Branch to use t3_clock1 + $0a if energization time is "in the past"                             
            ldx     temp20                  ; Energization time is valid, use it

            ;----------------------------------------------------
            ; Schedule the coil energization 
            ; time and store time in enerAbsTimeNext0
            ;----------------------------------------------------
L1762       stx     t3_outCmpWr             ; Schedule interrupt time on first output compare register  
            ldaa    t3_csr1                 ; Go to next output compare register                                                                                               
            stx     t3_outCmpWr             ; Schedule interrupt time on second output compare register 
            stx     enerAbsTimeNext0        ; Store actual time used                             

            ;--------------------------------------------------
            ; Reset the corresponding coil bit to 
            ; energize the coil at the specified time
            ;--------------------------------------------------
            ldaa    tdcMask1                ; a = $02 or $04
            asla                            ; a = $04 or $08
            coma                            ; a = ~($04 or $08)                            
            anda    t3_csr0                 ; reset that coil bit, i.e. energize that coil at the specified time                             
            staa    t3_csr0                 ; update t3_csr0                             

            ;-----------------------------------------------
            ; Set enerFlags = 0
            ; Although coil is energized, it seems we use 
            ; this value when rpm is low...
            ;-----------------------------------------------
            clra                            ;                             
            staa    enerFlags               ;                              
            bra     L1765                   ;                              

            ;------------------------------------------------------------------------------
            ; Update enerAbsTimeNext0 with its latest value if flag indicates 
            ; coil is energized or energization has been scheduled
            ; Makes sense to update the variable if energization time was actually used...
            ;------------------------------------------------------------------------------
L1763       brclr   enerFlags, #$03, L1765  ; Branch if flag indicates coil is not energized and energization is not scheduled
L1764       ldd     temp20                  ; d = temp20                                   
            std     enerAbsTimeNext0        ; enerAbsTimeNext0 = temp20                               

            ;-------------------------------------------
            ; Common branching place for all code above
            ;-------------------------------------------
            ;-------------------------------------------------------
            ; Update ignFallFlags, t3_csr0 and t1_csr
            ; Change cas edge detection polarity among others... 
            ;-------------------------------------------------------
L1765       andm    ignFallFlags, #$fe      ; Reset 0000 0001                               
            ldaa    t3_csr0                 ; a = t3_csr0                              
            anda    #$0c                    ; reset both coil bits, i.e. energize both coil at the specified time
            oraa    #$42                    ; set   0100 0010 ???                                                                                                  
            ldab    t1_csr                  ; b = t1_csr                                                                                                       
            andb    #$19                    ; reset 1110 0110, change cas detection polarity, enable injectors 5/6 bits???, reset injector and cas interrupt pending flags
            ldx     t1_inCapt               ; Clear input capture flag?
            staa    t3_csr0                 ; Update t3_csr0                                                                                                     
            stab    t1_csr                  ; Update t1_csr   
                                                                                                              
            ;-----------------------------------
            ; Reset instant knock sum???
            ;-----------------------------------
            andm    port6, #$fe             ; Reset instant knock sum???                                                                                             

            ;---------------------------------------------------------------------
            ; Reset engine rotating timer to 0.6sec or 1.2sec depending on 
            ; whether key is in start. If key is in start it means we are 
            ; cranking, rpm is therefore low and we need a longer timeout value...
            ;---------------------------------------------------------------------
            ldaa    #$18                    ; a = 0.6sec                                                                                                   
            brset   port3, #$40, L1766      ; Branch if key is not in start???                                                                                                      
            asla                            ; key in start, use a = 1.2sec                                                                                                    
L1766       staa    T40_engRot              ; T40_engRot = #$18 (0.6sec) or #$30 (1.2sec)

            ;----------------------------
            ; Update rev limiter flag
            ;----------------------------
            ldx     Tcas                    ; Tcas = Time(s) per engine revolution * 125000, rpm = (125000*60)/(2*Tcas)                               
            cpx     #$01f4                  ; Rev limiter (limit rpm = (125000*60)/(2*$01F4) = 7500)                                                     
            bcc     L1767                   ; branch if RPM lower than threshold (Tcas higher than threshold)
            orm     state3, #$04            ; RPM exceeds threshold, set bit                                
            bra     L1768                   ;                              
L1767       andm    state3, #$fb            ; RPM below threshold, reset bit                                

            ;-----------------------------
            ; Update cylinder1 TDC state
            ;-----------------------------
L1768       andm    tdcCasFlags, #$7f         ; Assume flag is 0                                 
            brclr   tdcCasFlags, #$08, L1769  ; branch if TDC was 0 last time

            ;------------------------------------------------
            ; TDC bit was 1 last time, check if it changed
            ;------------------------------------------------
            brset   port3, #$04, L1769      ; branch if current TDC bit is 1                               

            ;-------------------------------------------------------------------------------
            ; TDC bit was 1 last time and is now 0, update flag and reset counter (lower three bits)
            ;
            ; -> since we are executing this code on every falling edge of CAS pulses,
            ; we necessarily are on the cylinder #1 TDC
            ;-------------------------------------------------------------------------------
            orm     tdcCasFlags, #$80       ; 
            andm    tdcCasFlags, #$f8       ; Reset lower 3 bits of tdcCasFlags

            ;------------------------
            ; Update stored TDC bit
            ;------------------------
L1769       andm    tdcCasFlags, #$f7       ; Reset old TDC bit to 0
            brclr   port3, #$04, L1770      ; branch if current TDC bit is not set                               
            orm     tdcCasFlags, #$08       ; Current TDC bit set, update the flag with current value

            ;---------------------------------------------------------
            ; Decrement tdcCasFlags lower 3 bits if not already at 0
            ;---------------------------------------------------------
L1770       brclr   tdcCasFlags, #$07, L1771  ; Branch if lower 3 bits have reached 0                                
            dec     tdcCasFlags               ; Decrement lower 3 bits

            ;--------------------------------------------------------------------------------------------------
            ; Increment casCylIndex (loop from 0 to 3) and reset it to 0 if TDC detected on #1 cyl (tdcCasFlags.7 set)
            ;--------------------------------------------------------------------------------------------------
L1771       ldaa    casCylIndex               ;                              
            inca                              ;                             
            cmpa    #$04                      ;                             
            bcc     L1772                     ; Branch if new value >= 4                             
            brclr   tdcCasFlags, #$80, L1773  ; New value < 4, branch if no TDC detected                              
L1772       clra                              ; TDC detected, restart counter at 0                            
L1773       staa    casCylIndex               ;                              


            ;------------------------------------------------
            ; Update tdcCheck
            ; Decrement on every cas falling edge and 
            ; re-init to 8 on cylinder #1 TDC, tdcCheck
            ; should never reach 0 if TDC sensor is working
            ;------------------------------------------------
            ldaa    tdcCheck                  ;                              
            beq     L1774                     ; Branch if tdcCheck already 0                            
            deca                              ; a = tdcCheck                          
L1774       brclr   tdcCasFlags, #$80, L1775  ; branch to store if not cylinder #1 TDC                                  
            ldaa    #$08                      ; We are at cylinder #1 TDC, restart tdcCheck with 8                          
L1775       staa    tdcCheck                  ; Store new value                              

            ;---------------------
            ; Update oldAirCnt0
            ;---------------------
            ldd     airCnt0                                                 
            std     oldAirCnt0                                                 

            ;---------------------------------------------------------------
            ; Compute d = t1_t2_diff/8, 
            ; the time between the last time we received a airflow
            ; sensor pulse and the time when the current cas edge was 
            ; detected (t1_lastCas stored at the beginning of the interrupt) 
            ;
            ; If airCntNew0 is null (we did not count any air since the 
            ; last time we were here) then use d = Tcas??? 
            ;---------------------------------------------------------------
            ldd     airCntNew0              ;                                 
            bne     L1776                   ; Branch if airCntNew0 != 0                            
            ldd     Tcas                    ; airCntNew0=0, use d = Tcas??                           
            bra     L1777                   ;          
L1776       ldd     t1_lastCas              ; Get cas edge time value
            subd    t2_lastMas              ; Subtract last time mas interrupt was called, d = t1_lastCas - t2_lastMas = t1_t2_diff                                                        
            ldx     #T200_mas               ;                                                                    
            jsr     masFunc1                ; D = ~t1_t2_diff/8                                                       

            ;---------------------------------------------------------------
            ; Loop to scale D=t1_t2_diff (and X=t2_diff8 at the same time) 
            ; to fit in lower nibble only
            ;---------------------------------------------------------------
L1777       ldx     t2_diff8                ; X = t2_diff8                                                         
L1778       tsta                            ;                                                                                       
            beq     L1779                   ; Branch if high nibble=0                                                                
            lsrd                            ; high nibble<>0, divide by 2                                                           
            xgdx                            ; X<->D                                                                                 
            lsrd                            ; divide t2_diff8 by 2                                                                   
            xgdx                            ; X<->D                                                                                 
            bra     L1778                   ; At this point, X=t2_diff8/2, D=t1_t2_diff/2, loop back     
                                                    
            ;---------------------------------------------------------------------------
            ; At this point, D=scaledt1_t2_diff fits in lower nibble and X=scaledt2_diff8
            ;----------------------------------------------------------------------------
L1779       ldaa    #$9c                    ; A=$9C, B=scaledt1_t2_diff                                         
            mul                             ; D = scaledt1_t2_diff * $9C                                        
            xgdx                            ; X = scaledt1_t2_diff * $9C, D=scaledt2_diff8

            ;----------------------------------------------------------------
            ; Loop to scale X=scaledt1_t2_diff*$9C to fit in lower nibble
            ; scales D = scaledt2_diff8 by the same amount
            ;----------------------------------------------------------------
L1780       tsta                            ;                                
            beq     L1781                   ;                                 
            lsrd                            ;                                
            xgdx                            ;                                
            lsrd                            ;                                
            xgdx                            ;                                
            bra     L1780                   ;                                 

            ;---------------------------------------------------------------
            ; At this point, D=scaledt2_diff8 and X=scaledt1_t2_diff * $9C
            ; Compute airQuantumRemainder = scaledt1_t2_diff/scaledt2_diff8 * $9C
            ;---------------------------------------------------------------
L1781       stab    temp8                   ; temp8 = scaledt2_diff8                                                       
            xgdx                            ; D=scaledt1_t2_diff * $9C, X=scaledt2_diff8                                   
            div     temp8                   ; D=D/temp8 = scaledt1_t2_diff * $9C / scaledt2_diff8?                                                                   
            bcs     L1782                   ; Branch if overflow                                                                               
            lsr     temp8                   ; Check for ???                                                                              
            cmpa    temp8                   ;                                                                               
            bcs     L1783                   ; 
            incb                            ; 
            bne     L1783                   ;                                                                              
L1782       ldab    #$ff                    ; overflow, use max  
                           
            ;------------------------------------------------------------------------
            ; At this point, b = airQuantumRemainder = scaledt1_t2_diff/scaledt2_diff8 * $9C             
            ; Check if we should use it
            ;------------------------------------------------------------------------
L1783       cmpb    airQuantum              ;                              
            bcs     L1784                   ; Branch if airQuantumRemainder  < airQuantum, which means we can use it
            ldab    airQuantum              ; airQuantumRemainder >= airQuantum (in theory, I suppose at most it should only be equal to it...) use b=airQuantum                             
            clr     airQuantum              ; airQuantum=0 (since we "transfered" all of it to b)                             
            bra     L1785                   ;                              

            ;------------------------------------------------------------------------
            ; At this point airQuantumRemainder < airQuantum
            ; and b = airQuantumRemainder = scaledt1_t2_diff/scaledt2_diff8 * $9C
            ; 
            ; We are going to use airQuantumRemainder in this calculation cycle. 
            ; Subtract it from airQuantum. What is left in airQuantum 
            ; is going to be used as the startup value for the next airflow
            ; calculation cycle. Basically we don't want to loose any air in
            ; the calculations... 
            ;------------------------------------------------------------------------
L1784       ldaa    airQuantum              ; a = airQuantum
            sba                             ; a = airQuantum -  airQuantumRemainder
            staa    airQuantum              ; airQuantum = old airQuantum - airQuantumRemainder, basically we subtract what we are going to use

            ;------------------------------------------------------- 
            ; Finish calc and scale airQuantumRemainder if required
            ;------------------------------------------------------- 
L1785       clra                              ; d = airQuantumRemainder (high part=0)                            
            brclr   masCasFlags, #$80, L1786  ; Branch if no scaling                                       
            asld                              ; scale d = airQuantumRemainder * 2                                            

            ;-----------------------------------------------------------------------
            ; At this point, d = airQuantumRemainder, 
            ; add it for a final time to airCntNew0, also check for minimum value
            ;-----------------------------------------------------------------------
L1786       addd    airCntNew0              ; d = airQuantumRemainder + airCntNew0                                                           
            cmpd    airCntMin0              ;                                                           
            bcc     L1787                   ; Branch if airCntNew0 + airQuantumRemainder > airCntMin0                                                          
            ldd     airCntMin0              ; Use airCntMin0                                                          
L1787       std     airCntNew0              ; airCntNew0 =   max(airQuantumRemainder+airCntNew0, airCntMin0)

            ;---------------------------------------------------------------------------------
            ; Adjust airCntNew0 when mafRaw below 50Hz:
            ; If mafRaw below 50Hz and (airCnt0-airCntNew0) >= $004e then airCntNew0 = (airCnt0-$0010)
            ; Limits the downward rate of change of airCntNew0 under rapidly decreasing air flow conditions???
            ;---------------------------------------------------------------------------------
            ldaa    mafRaw                  ; a = mafRaw                                                
#ifdef masLog2X                              
            cmpa    #$04                     
#else                                        
            cmpa    #$08                                                  
#endif                                       
            bcc     L1788                   ; Branch if mafRaw > 50Hz (no adjustment)
            ldd     airCnt0                 ; mafRaw<50Hz, d = airCnt0
            subd    airCntNew0              ; d = airCnt0-airCntNew0 
            bcs     L1788                   ; Branch if airCnt0 < airCntNew0 (no adjustment)
            cmpd    #$004e                  ; airCnt0 >= airCntNew0, check difference
            bcs     L1788                   ; Branch if (airCnt0-airCntNew0)<$004e (no adjustment)
            ldd     airCnt0                 ; (airCnt0-airCntNew0)>=$004e, subtract $10
            subd    #$0010                  ;                               
            std     airCntNew0              ; airCntNew0 = (airCnt0-$0010)                              

            ;--------------------------------------------------------
            ; Section below is to update airCnt0:airCnt1:airCnt2 
            ; (filtered air count) from airCntNew0:airCntNew1 (latest 
            ; air count received from aiflow sensor)
            ;--------------------------------------------------------
            ;------------------------------------------------------------
            ; Multiply airCnt0:airCnt1:airCnt2 by 8 * airFiltFact/256
            ;------------------------------------------------------------
L1788       ldaa    airFiltFact             ;                                    
            staa    temp8                   ; temp8=airFiltFact                               
            ldd     airCnt1                 ; d = airCnt1:airCnt2                                 
            asld                            ;                              
            rol     airCnt0                 ;                                
            asld                            ;                             
            rol     airCnt0                 ;                                
            asld                            ; d = 8*[airCnt1:airCnt2]
            rol     airCnt0                 ; airCnt0 = 8*airCnt0                                 
            ldab    temp8                   ; b = airFiltFact                               
            mul                             ; d = airFiltFact * (8*[airCnt1:airCnt2])/256
            std     airCnt1                 ; airCnt1:airCnt2 =  airFiltFact * (8*[airCnt1:airCnt2])/256
            ldaa    airCnt0                 ;                                 
            ldab    temp8                   ;                               
            mul                             ; d = airCnt0 * airFiltFact                             
            addb    airCnt1                 ; Add lower part                                 
            adca    #$00                    ; Propagate carry
            std     airCnt0                 ; Store final result, 8*[airCnt0:airCnt1:airCnt2] * airFiltFact/256

            ;------------------------------------------------------------------
            ; Multiply airCntNew0:airCntNew1 by 4 with overflow check
            ;------------------------------------------------------------------
            ldd     airCntNew0              ;                              
            asld                            ;                             
            bcs     L1789                   ;                              
            asld                            ;                             
            bcc     L1790                   ;                              
L1789       ldaa    #$ff                    ; Use max
L1790       std     airCntNew0              ;                              

            ;-----------------------------------------------------------------------------------------------------------
            ; Add 2*(256-airFiltFact)*4*[airCntNew0:airCntNew1] to 8*[airCnt0:airCnt1:airCnt2] * airFiltFact/256
            ; with overflow check
            ;-----------------------------------------------------------------------------------------------------------
            ldaa    temp8                   ; Still contains airFiltFact ($d1 or $e4 from code)?                               
            nega                            ;                               
            asla                            ; a = 2*(256-airFiltFact) -> $d1->$5e   $e4->$38    209->94   228->56 
            mul                             ; d = 2*(256-airFiltFact) * airCntNew1
            addd    airCnt1                 ;                                        
            std     airCnt1                 ;                                 
            ldaa    airCnt0                 ;                                 
            adca    #$00                    ;                             
            bcc     L1791                   ; Branch if no overflow                             
            ldaa    #$ff                    ; Use max if overflow                            
L1791       staa    airCnt0                 ;                    

            ldaa    temp8                  ; Still contains airFiltFact                              
            nega                            ;                             
            asla                            ;                             
            ldab    airCntNew0              ;                              
            mul                             ;                             
            addd    airCnt0                 ;                                 
            bcc     L1792                   ; Branch if no overflow                                 
            ldd     #$ffff                  ; Use max if overflow                                    

            ;-------------------------------------------------------------------------------------------------------------------
            ; At this point, D:airCnt2 contains result from above: 
            ; D:airCnt2 = 8*[airCnt0:airCnt1:airCnt2] * airFiltFact/256 + 2*4*(256-airFiltFact)*[airCntNew0:airCntNew1] 
            ; Divide it by 8 and store it. 
            ; If no  pulse accumulator interrupts were receive, use airCntDef
            ;-------------------------------------------------------------------------------------------------------------------
L1792       lsrd                            ;                              
            ror     airCnt2                 ;                                 
            lsrd                            ;                             
            ror     airCnt2                 ;                                 
            lsrd                            ;                             
            ror     airCnt2                 ; Divide D:airCnt2 by 8
            brclr   state3, #$02, L1793     ; Branch if pulse accumulator interrupts received
            ldab    airCntDef               ; No pulse accumulator interrupts                              
            clra                            ;                             
            asld                            ;                             
            asld                            ;                             
            asld                            ;                             
L1793       std     airCnt0                 ; Store airCnt0:airCnt1, airCnt2 was stored earlier                                 

            ;-------------------------------------------------------------------------------------------------------------------------------------------
            ; At this point: 
            ;
            ; [airCnt0:airCnt1:airCnt2]    = 1/8 * ( 8*[airCnt0:airCnt1:airCnt2] * airFiltFact/256 + 2*4*(256-airFiltFact)*[airCntNew0:airCntNew1] )
            ;                              = 1/8 * ( 8*[airCnt0:airCnt1:airCnt2] * airFiltFact/256 + 256/256*2*4*(256-airFiltFact)*[airCntNew0:airCntNew1] )
            ;                              = 1/8 * ( 8*[airCnt0:airCnt1:airCnt2] * airFiltFact/256 + 8*(256-airFiltFact)/256 * 256*[airCntNew0:airCntNew1] )
            ;                              = [airCnt0:airCnt1:airCnt2] * airFiltFact/256 + (256-airFiltFact)/256 * 256*[airCntNew0:airCntNew1]
            ;                              = [airCnt0:airCnt1:airCnt2] * alpha + (1-alpha) * 256*[airCntNew0:airCntNew1]
            ;
            ;                              = alpha * oldAirCnt24bits + (1-alpha) * scaledNewAirCnt16bits
            ;
            ;                                        where alpha = airFiltFact/256, 0<=alpha<=1, 
            ;
            ; This is exponential averaging of [airCnt0:airCnt1:airCnt2] with [airCntNew0:airCntNew1]*256 as input 
            ;
            ;-------------------------------------------------------------------------------------------------------------------------------------------

            ;-----------------------------------------------------------------
            ; If engine is notRotating or startingToCrank then ignore 
            ; airCnt0 we just calculated and use airCntMax*8 instead 
            ;-----------------------------------------------------------------
            ldab    airCntMax               ; d = airCntMax                                   
            clra                            ;                             
            asld                            ;                             
            asld                            ;                             
            asld                            ; d = 8*airCntMax                             
            brset   state3, #$11, L1794     ; Branch if notRotating or startingToCrank -> Always use airCntMax*8 in that case?                              


            ;-------------------------------------------------
            ; Engine is running, cap airCnt0 with airCntMax*8
            ;-------------------------------------------------
            cmpd1   airCnt0                 ;                                 
            bcc     L1795                   ; Branch if airCntMax*8 >= airCnt0                               
L1794       std     airCnt0                 ; Store airCntMax in airCnt0 

            ;----------------------------------------------------------------------
            ; Update oldAirCnt0 if no pulse accumulator interrupts were received????
            ;----------------------------------------------------------------------
L1795       brclr   state3, #$02, L1796     ; Branch if pulse accumulator interrupts are being received                               
            ldd     airCnt0                 ; No pulse accumulator interrupts received, store airCnt0 in oldAirCnt0???                                 
            std     oldAirCnt0              ;                                    

            ;-----------------------------------------
            ; Re-init airCntNew0, start a new cycle
            ;-----------------------------------------
L1796       clra                                                         
            clrb                                                         
            std     airCntNew0     
             
            ;---------------------------------------------------------------------------------                  
            ; Execute the coil interrupt routine if an output capture interrupt is pending                       
            ;                                                                                                    
            ; Might be called from here because we are about to spend 
            ; a lot of time to calculate airflow and injectors???? I assume here
            ; that by doing so, the pending interrupt will be cleared?
            ;---------------------------------------------------------------------------------                                                              
            brclr   t3_csr1, #$40, L1797   ; Branch if no interrupt pending                                   
            jsr     coilFunc                   ;                              

            ;-------------------------------------------------------------------------------------
            ; Execute the pulse accumulator routine if an interrupt is pending
            ;
            ; At this point, airQuantum contains whatever air remains to be counted
            ; from the time the current CAS interrupt occured up to the time the next
            ; mas interrupt will happen (the next airflow sensor pulse). If the mas interrupt
            ; is pending then this air should already have been added. Do it now. I assume
            ; that by doing so, the pending interrupt will be cleared?
            ;
            ; If no interrupt is pending then the remaining air will be added when the
            ; next mas interrupt will occur, which is the normal way.
            ;
            ; In both cases airQuantum is re-initialized to its maximum value when masProc 
            ; is executed
            ;-------------------------------------------------------------------------------------
L1797       brclr   t2_csr, #$80, L1798     ; Branch if no interrupt pending                                 
            jsr     masProc                 ;                              

            ;------------------------------------------------------------------------------------
            ; Compute a kind of airCnt0 derivative (acceleration and decceleration)
            ; Update airDiffPos or airDiffNeg with airFlowDifference = abs(airCnt0-oldAirCnt0)
            ; airDiffPos is updated when airCnt0-oldAirCnt0 >= 0
            ; airDiffNeg is updated when airCnt0-oldAirCnt0 < 0
            ;------------------------------------------------------------------------------------
L1798       ldx     #airDiffPos             ;                               
            ldd     airCnt0                 ; d = airCnt0                                
            subd    oldAirCnt0              ; d = airCnt0-oldAirCnt0                             
            bcc     L1799                   ; Branch if result positive
            coma                            ; Result negative, change sign                           
            comb                            ;                            
            addd    #$0001                  ; d = oldAirCnt0-airCnt0
            inx                             ; x =  x + 1                           
L1799       tsta                            ; Check for overflow in a (we want result in b only)                           
            beq     L1800                   ; Branch if a=0 (b contains difference)                             
            ldab    #$ff                    ; a not null->overflow, use b = maximum
L1800       cmpb    $00,x                   ; 
            bls     L1801                   ; Branch if abs(airCnt0-oldAirCnt0) <= airDiffPos or airDiffNeg
            stab    $00,x                   ; Store new value of airDiffPos or airDiffNeg
                                        
            ;---------------------------------------------------------------------------
            ; Decide what value we are going to use for injPw (0, injPwStart or normal)
            ;---------------------------------------------------------------------------
L1801       brclr   state3, #$01, L1802     ; Branch if startingToCrank clear                                
            ldd     injPwStart              ; Engine startingToCrank, use injPwStart                              
            bra     L1803                   ; Do not compute injPw from airflow                              
L1802       brclr   state3, #$3c, L1804     ; startingToCrank clear, branch to compute normal injPw from airflow if all clear: "rotatingStopInj but not runningFast" and "notRotating" and "rotatingStopInj" and "rev limiter active"
            clra                            ; Use injPw=0 if rev limiter is active or if engine is notRotating, rotatingStopInj or "rotatingStopInj and not runningFast" 
            clrb                            ;                             
L1803       std     injPw                   ;                              
            bra     L1807                   ;                              


            ;----------------------------------------------------------------
            ; Compute injector pulsewidth for normal engine conditions
            ;
            ; injPw =  [airCnt0:airCnt1] * injFactor/256, 16 bit multiply
            ;----------------------------------------------------------------
L1804       ldaa    airCnt1                 ; a = airCnt1                                 
            ldab    injFactor+1             ; b = injFactor1                                    
            mul                             ; d = airCnt1*injFactor1                             
            tab                             ; b = airCnt1*injFactor1/256                             
            clra                            ; d = airCnt1*injFactor1/256                            
            std     injPw                   ; injPw = airCnt1*injFactor1/256                              
            ldaa    airCnt1                 ;                                 
            ldab    injFactor               ;                                  
            mul                             ;                             
            addd    injPw                   ;                              
            bcs     L1805                   ;                              
            std     injPw                   ;                              
            ldaa    airCnt0                 ;                                 
            ldab    injFactor+1             ;                                    
            mul                             ;                             
            addd    injPw                   ;                              
            bcs     L1805                   ;                              
            std     injPw                   ;                              
            ldaa    airCnt0                 ;                                 
            ldab    injFactor               ;                                  
            mul                             ;                             
            addb    injPw                   ;                              
            adca    #$00                    ; Propagate carry                            
            beq     L1806                   ; Branch if no overflow                             
L1805       ldab    #$f0                    ; Overflow, use max of ~$f000 (61ms) in case of overflow                             
L1806       stab    injPw                   ;                              

            ;----------------------
            ; Compute accEnrDiffT
            ;----------------------
L1807       ldx     #L2040                   ; x points to L2040                              
            ldab    oldAirCnt0               ; b = oldAirCnt0/256 (high part only...)                                  
            cmpb    #$05                     ;                            
            bcs     L1808                    ; Branch if below max                            
            ldab    #$05                     ; Use max                           
L1808       abx                              ; x = L2040 + min(oldAirCnt0, 5)                            
            ldab    $00,x                    ; b = L2040(oldAirCnt0/256)                            
            stab    accEnrDiffT              ; accEnrDiffT = L2040(oldAirCnt0/256)                             

            ;------------------------------------------------------------------------
            ; Update accEnr
            ;
            ; At first accEnr is decreased by a fixed factor (exponentially)
            ; on each iteration. When it reaches a certain level, it this 
            ; then held constant for the duration of a timer and then 
            ; decremented by 1 to 0. First do the exponential part...
            ;------------------------------------------------------------------------
            ldab    accEnr                  ; b = accEnr                             
            beq     L1811                   ; Branch if accEnr = 0                            
            ldaa    accEnrDecay             ; a = accEnrDecay                            
            mul                             ; d = accEnrDecay * accEnr                           
            tab                             ; b = accEnr * accEnrDecay/256                            
            ldaa    accEnr                  ; a = accEnr                             
            sba                             ; a = accEnrNew = accEnr - accEnr * accEnrDecay/256 = accEnr * (1-accEnrDecay/256)                             
            cmpa    #$02                    ;                            
            bcc     L1811                   ; Branch if accEnrNew >= 2                            

            ;-------------------------------------------------------------------
            ; accEnr - accEnr * accEnrDecay/256 < 2 (which means accEnr much bigger than 2)
            ; Just decrement accEnr by 1 if  accEnrTmr2=0 else don't change it
            ;
            ; Basically hold the accEnr to current value for 4 or 5 iterations 
            ; and then start decrease it by 1 to 0
            ;-------------------------------------------------------------------
            ldaa    accEnrTmr2              ; 
            beq     L1810                   ;                             
            deca                            ;                            
            bne     L1812                   ;                             
L1810       ldab    accEnr                  ;                              
            decb                            ;                            
L1811       stab    accEnr                  ;                              

            ;----------------------------------
            ; Update accEnrTmr2 from ect
            ;----------------------------------
            ldaa    #$04                    ; a = 4                           
            ldab    ectFiltered             ; b = ectFiltered                                  
            cmpb    #$80                    ; 21degC                             
            bcs     L1812                   ; Branch if temperature(ectFiltered) >= 21degC
            ldaa    #$05                    ; temperature <21degC                           
L1812       staa    accEnrTmr2              ; re-init accEnrTmr2 with 5                            

            ;--------------------------------------
            ; Decrement accEnrTimer if not yet 0
            ;--------------------------------------
            ldaa    accEnrTimer             ; 
            beq     L1813                   ; Branch if accEnrTimer = 0                             
            deca                            ;                             
            staa    accEnrTimer             ;                              

            ;---------------------------------------------------
            ; Re-init accEnrTimer to 4 if airCnt0>=accEnrMinAf 
            ;---------------------------------------------------
L1813       ldd     airCnt0                 ;                                 
            cmpd    accEnrMinAf             ;                                     
            bcc     L1814                   ; Branch if airCnt0>=accEnrMinAf 
            ldaa    #$04                    ;                              
            staa    accEnrTimer             ; re-init accEnrTimer = 4                              

            ;----------------------------
            ; Bail if engine not running 
            ;----------------------------
L1814       brclr   state3, #$13, L1815     ; Branch if notRotating and startingToCrank and "no pulse accumulator interrupts" clear                               
            clr     accEnr                  ; One of them set, no accEnr should be applied
            jmp     L1825                   ; Bail                              

            ;---------------------------------------------------
            ; Skip section if injPw==0
            ;---------------------------------------------------
L1815       ldd     injPw                   ;                              
            bne     L1816                   ; Branch if injPw !=0                             
            jmp     L1825                   ; Bail                              

            ;---------------------------------------------------
            ; Section to factor acceleration/deceleration enrichment
            ; to injPw (when injPw!=0)
            ;---------------------------------------------------
            ;---------------------------------------------------
            ; Compute diff = airCnt0-oldAirCnt0
            ; Check if positive or negative
            ;---------------------------------------------------
L1816       clr     decEnr                  ; Assume decEnr = 0
            ldd     airCnt0                 ; d = airCnt0                                 
            subd    oldAirCnt0              ; d = airCnt0-oldAirCnt0                                   
            bcs     L1820                   ; Branch if result negative                             

            ;---------------------------------------------------
            ; diff>=0 (airCnt0 increased or is unchanged)
            ; Check if conditions are met to apply acceleration enrichment
            ;---------------------------------------------------
            tst     accEnrTimer             ; Check if timer expired
            beq     L1819                   ; Bail if accEnrTimer expired (airflow has been below absolute threshold for more than 4 iterations)                             
            brset   port3, #$80, L1819      ; Bail if idle switch is on                              

            ;----------------------------------
            ; Check diff against max of $48
            ;----------------------------------
            tsta                            ; test hi part of diff                            
            bne     L1817                   ; Branch if diff >=256 (hi(diff)!=0) -> use $48                             
            cmpb    #$48                    ; diff <256 check low part against $48                           
            bcs     L1818                   ; Branch if diff <$48                                
L1817       ldab    #$48                    ; use $48                             

            ;---------------------------------------------------------------------------
            ; At this point b contains diff=min(airCnt0-oldAirCnt0,$48)
            ;
            ; Update accEnr with diff if diff is big enough (big increase in airflow)
            ; and higher than old accEnr
            ;---------------------------------------------------------------------------
L1818       cmpb    accEnrDiffT             ;                              
            bls     L1819                   ; Branch if diff<=accEnrDiffT                             
            cmpb    accEnr                  ; diff>accEnrDiffT store new value if higher than old one                             
            bls     L1819                   ;                              
            stab    accEnr                  ; accEnr = min(airCnt0-oldAirCnt0,$48)
L1819       bra     L1822                   ;                              

            ;---------------------------------------------------------
            ;
            ;
            ; airCnt0 decreased check if below absolute threshold
            ;
            ;
            ;---------------------------------------------------------
L1820       ldd     airCnt0                 ; d = airCnt0                               
            cmpd    accEnrMinAf             ;                              
            bcc     L1822                   ; Bail if airCnt0 >= accEnrMinAf                            

            ;---------------------------------------------------------
            ; airCnt0 decreased and is below absolute threshold
            ; compute diff = min(airCnt0-oldAirCnt0,$ff)
            ;---------------------------------------------------------
            ldd     oldAirCnt0              ;                                    
            subd    airCnt0                 ; d = oldAirCnt0-airCnt0                                
            tsta                            ; test hi part (diff>=256?)                            
            beq     L1821                   ; Branch if below max
            ldab    #$ff                    ; Use max of $ff                            

            ;---------------------------------------------------------------------------
            ; Clear accEnr if diff is big enough (big decrease in airflow)
            ; At this point b contsains diff=min(airCnt0-oldAirCnt0,$ff)
            ;---------------------------------------------------------------------------
L1821       cmpb    accEnrDiffT             ;                              
            bls     L1822                   ;                              
            stab    decEnr                  ; decEnr = min(airCnt0-oldAirCnt0,$ff)
            clr     accEnr                  ; accEnr = 0                              

            ;---------------------------------------------------
            ; Section to add acceleration enrichment to injPw or
            ; reduce it in case of deceleration
            ;
            ; Check if min(airCnt0-oldAirCnt0,$ff) >0
            ;---------------------------------------------------
L1822       ldab    decEnr                  ; 
            bne     L1823                   ; Branch if decEnr > 0 (reduce injPw)                            

            ;---------------------------------------------------------------
            ; decEnr = 0, increase or do not change injPw
            ;
            ; Apply enrichment: 
            ;     injPw = injPw + accEnr*accEnrFact/256
            ;           = injPw + 8 * min(airCnt0-oldAirCnt0,$48) * injMasComp/256 * t_accEnr1(rpm)/128 * [t_accEnr2a(ect) or t_accEnr2b(ect)]/128 * baroFact/128
            ;---------------------------------------------------------------
            ldaa    accEnr                  ; a = accEnr                               
            ldab    accEnrFact              ; b = accEnrFact                            
            mul                             ; d = accEnr * accEnrFact                             
            xgdx                            ; x = accEnr * accEnrFact                           
            ldaa    accEnr                  ;                               
            ldab    accEnrFact+1            ;                              
            mul                             ; d = accEnr * L0109                            
            tab                             ; b = accEnr * L0109/256                            
            abx                             ; x = accEnr * accEnrFact +  accEnr * L0109/256 = accEnr*(accEnrFact + L0109/256)                            
            xgdx                            ; d = accEnr*(accEnrFact + L0109/256)
            addd    injPw                   ; d = injPw + accEnr*accEnrFact/256
            bcc     L1824                   ; Bail if no overflow                             
            ldaa    #$f0                    ; Overflow, use max of $f000                            
            bra     L1824                   ; Bail
                                          
            ;---------------------------------------------------
            ; decEnr > 0. decrease injPw
            ;
            ; Apply reduction 
            ;      injPw = injPw - decEnr*decEnrFact/256
            ;            = injPw +  8 * min(airCnt0-oldAirCnt0,$ff) * injMasComp/256 * t_decEnr1(rpm)/128 * t_decEnr2(ect)/128 * baroFact/128
            ;---------------------------------------------------
L1823       ldaa    decEnr                  ; a = decEnr                             
            ldab    decEnrFact              ; b = decEnrFact                             
            mul                             ; d = decEnr * decEnrFact                               
            xgdx                            ; x = decEnr * decEnrFact                            
            ldaa    decEnr                  ;                              
            ldab    decEnrFact+1            ;                              
            mul                             ; d = decEnr * L010b                            
            tab                             ; b = decEnr * L010b/256                            
            abx                             ; x = decEnr * decEnrFact + decEnr * L010b/256                            
            stx     temp8                   ; temp8:dTemp2 = decEnr * decEnrFact + decEnr * L010b/256  = decEnr*(decEnrFact+L010b/256)                             
            ldd     injPw                   ; d = injPw                             
            subd    temp8                   ; d = injPw - decEnr*decEnrFact/256                               
            bhi     L1824                   ; Bail if positive                             
            clra                            ;                             
            ldab    #$01                    ; Use min of $0001                            
L1824       std     injPw                   ; Update injPw                             

            ;---------------------------------------------------
            ; Skip section if injPw==0
            ;---------------------------------------------------
L1825       ldd     injPw                   ;                              
            bne     L1826                   ; Branch to do section when injPw!=0                            
            jmp     L1845                   ; bail to next section                            

            ;--------------------------------------------------------
            ; injPw != 0, increment injCount if not already at max(255)
            ;--------------------------------------------------------
L1826       inc     injCount                ;                                 
            bne     L1827                   ; Branch if injCount!=0                               
            dec     injCount                ; injCount was 255 and is now 0, go back to max of 255                                

            ;-------------------------------------------------
            ; Load injPw in d and divide by 4 if necessary???
            ;-------------------------------------------------
L1827       clr     newInjToAct               ; newInjToAct = 0                               
            ldd     injPw                     ;                              
            brset   state3, #$80, L1828       ; Branch if startingToCrankColdEngine                                
            brclr   tdcCasFlags, #$07, L1829  ; Branch if down counter = 0 (first TDC on cyl. #1 was already encoutered)                               

            ;-------------------------------------------------------------------------------
            ; Seems we are startingToCrank (TDC #1 not yet encountered) but engine is 
            ; not cold so divide injPw by 4 since the value it constains(injPwStart) 
            ; was multiplied by 4 in injPwStart culculations, why???
            ;-------------------------------------------------------------------------------
            lsrd                            ; 
            lsrd                            ; d = injPw/4 = injPwStart                              
L1828       orm     newInjToAct, #$80       ; Set flag indicating we should be doing simultaneous injection

            ;-------------------------------------------------------
            ; Add injector deadtime and check for max and min value
            ;-------------------------------------------------------
L1829       jsr     addDeadtime             ; Add deadtime to d
            cmpa    #$ea                    ;                             
            bcs     L1830                   ; Branch if d < $ea00
            ldaa    #$ea                    ;                             
            clrb                            ; Too big, use max of d=$ea00 (60ms)                            
L1830       cmpd    #$0514                  ;                               
            bcc     L1831                   ; Branch if above minimum                              
            ldd     #$0514                  ; Too small, use minimum of d=$0514 (1.3ms)                               
L1831       std     injPw                   ; Store new value

            ;--------------------------------------------------------------------------------
            ; Schedule all 4 injector interrupts and bail if in simultaneous injection mode
            ;--------------------------------------------------------------------------------
            brclr   newInjToAct, #$80, L1832 ; Branch if sequential injection                                
            orm     newInjToAct, #$0f        ; Simultaneous injection, set mask corresponding to all 4 injectors
            jsr     schedInjSim              ; Schedule simultaneous injection interrupts                             
            jmp     L1845                    ; Bail to exit routine

            ;---------------------------------------------------
            ; At this point we are in sequential injection mode
            ;---------------------------------------------------
            ;------------------------------------------------------------------------------------
            ; Get the injector mask of the injector to activate for this particular CAS interrupt
            ; Injector for cylinder #1 starts injecting on the CAS falling edge of cylinder #3, 
            ; i.e. at the end on #1 combustion cycle/start of #1 exhaust cycle
            ;
            ;   casCylIndex   Cylinder number   Injector number       mask
            ;                 having its TDC    to activate on
            ;                 closest to CAS    CAS falling edge
            ;                 falling edge       
            ;        0             1                  2                $08
            ;        1             3                  1                $01
            ;        2             4                  3                $02
            ;        3             2                  4                $04
            ;
            ;------------------------------------------------------------------------------------
L1832       ldx     #t_cylMask              ; table content: [$08 $01 $02 $04] -> injector numbers: 2 1 3 4                            
            ldab    casCylIndex             ; b = casCylIndex                             
            abx                             ; x = t_cylMask + casCylIndex                            
            ldaa    $00,x                   ; a has one bit set to indicate which injector to use (one of $08 $01 $02 $04)                            

            ;-------------------------------------------------------
            ; Reset the mask if engine not running or if
            ; disabled by an obd command or if ignition is not happening
            ;-------------------------------------------------------
            brset   state3, #$11, L1833        ; Branch if notRotating or startingToCrank                                
            brclr   coilChkFlags, #$80, L1833  ; Branch if no ignition error found
            anda    coilChkFlags               ; Reset the injectors corresponding to missing ignition signal
L1833       anda    obdInjCmd                  ; Reset injector if disabled by OBD command                            

            ;-------------------------------------------------------
            ; Update newInjToAct, injToAct and last_t1t2_clk
            ;-------------------------------------------------------
            staa    newInjToAct             ; newInjToAct = injector to activate                               
            oraa    injToAct                ;                                
            staa    injToAct                ; injToAct = injToAct | newInjToAct
            ldaa    t1t2_clk                ;                                 
            staa    last_t1t2_clk           ; last_t1t2_clk = t1t2_clk/256 (current timer 1 clock?)                              

            ;----------------------------------------------------------------
            ; Branch to section depending on new injector to activate
            ;----------------------------------------------------------------
            brset   newInjToAct, #$0a, L1839   ; Branch if injector to activate is #2 or #3                                 
            brclr   newInjToAct, #$05, L1845   ; Bail if remaining injector #1 and #4 don't need activation either                                

            ;----------------------------------------------------------------
            ; Injector to activate is #1 or #4, check if already activated
            ;----------------------------------------------------------------
L1833b      brclr   port2, #$02, L1834      ; Branch if injector #1 activated (reverse logic)                               
            brset   port1, #$08, L1838      ; Branch if injector #4 deactivated (reverse logic)

            ;------------------------------------------------------------------------------
            ; Injector #1 or #4 already activated
            ;
            ; Check how much time remains before next interrupt occurs
            ;------------------------------------------------------------------------------
L1834       ldd     t1_outCmpWr             ; d = nextInterruptTime                                   
            subd    t1t2_clk                ; remainingTime  = d = nextInterruptTime - t1t2_clk                                  
            cmpd    #$0032                  ;                               
            bcs     L1835                   ; Branch if remainingTime < $0032 (50us)                            
            cmpd    #$00c8                  ;                               
            bcc     L1836                   ; Branch if remainingTime >= $00c8 (200us)                             

            ;--------------------------------------------------------
            ; 50us <= remainingTime < 200us, remaining time before the
            ; next interrupt is long enough to allow us to do something 
            ; but is not so long that activation will be too late...
            ;
            ; Enable injector activation bit and compute deactivation 
            ; time as  nextInterruptTime + injPw Since the injector 
            ; will be enabled when the interrupt occur, very shortly.
            ; Then exit this interrupt.
            ;--------------------------------------------------------
            bsr     actDeact14             ; Enable injector activation bit and compute deactivation time                                   
            bra     L1845                  ; Bail of interrupt                            

            ;--------------------------------------------------------
            ; remainingTime < $0032 (50us). remaining time before the
            ; next interrupt is too short to do what we need to do... 
            ; just wait for the interrupt to occur using an infinite 
            ; loop (2500 cycles?)
            ;--------------------------------------------------------
L1835       brclr   t1_csr, #$40, L1835     ;                                
            ;--------------------------------------------------------------------------------
            ; Interrupt has been triggered we can now proceed with activation
            ;--------------------------------------------------------------------------------

            ;------------------------------------------------------------------------------------
            ; At this point the remainingTime before the next interrupt is larger than 200us
            ; or it was smaller than 50us but we waited for the interrupt to occur. In both
            ; cases, we are certain an interrupt will no happen right away, just do what needs 
            ; doing...
            ;------------------------------------------------------------------------------------
            ;---------------------------------------------------------------------------
            ; First check if an injector is already activated and if so, just reflect 
            ; that fact in the activation bits (such that we don't change that injector
            ; state when we activate a new injector...)???
            ;---------------------------------------------------------------------------
L1836       brset   port2, #$02, L1837      ; Branch if injector #1 is deactivated                                
            andm    t1_csr, #$fe            ; injector #1 is activated, enable activation bit for it
L1837       brset   port1, #$08, L1838      ; Branch if injector #4 is deactivated                              
            andm    t2_csr, #$df            ; injector #4 is activated, enable activation bit for it

            ;-----------------------------------------------------------------
            ; Enable the activation bit for the new injector #1 or #4.
            ; Schedule an interrupt for "now + 22us" to activate them.
            ; Compute its deactivation time and schedule an interrupt for it
            ;
            ; I assume here that the 22us delay is small enough that it ensures
            ; the injector activation will occur before the deactivation is scheduled???
            ; not sure if interrupt subroutine is called in that case since we are 
            ; already in interrupt??????????? 
            ;-----------------------------------------------------------------
L1838       ldd     t1t2_clk                ; d = t1t2_clk (current time)                                  
            addd    #$0016                  ; activationTime   d = t1t2_clk + $16 (22us)
            std     t1_outCmpWr             ; Schedule interrupt at t1_outCmpWr = t1t2_clk + $16, i.e. activationTime = now + 22us                                  
            bsr     actDeact14              ; Enable new injector activation bit and compute deactivation time                                   
            jsr     schedDeact14            ; Schedule deactivation time                            
            bra     L1845                   ; Bail
                                                        
            ;-----------------------------------------------------
            ; Injector to activate is #2 or #3 
            ; Logic is identical to #1 #4 injectors 
            ; above starting at L1833b ......
            ;-----------------------------------------------------
L1839       brclr   port1, #$02, L1840      ; Injector 3                               
            brset   port1, #$04, L1844      ; Injector 2                               
L1840       ldd     t2_outCmpWr             ;                                    
            subd    t1t2_clk                ;                                 
            cmpd    #$0032                  ;                               
            bcs     L1841                   ;                              
            cmpd    #$00c8                  ;                               
            bcc     L1842                   ;                              
            bsr     actDeact23              ;                                   
            bra     L1845                   ; 
L1841       brclr   t2_csr, #$40, L1841     ; Infinite loop waiting for interrupt to be triggered                               
L1842       brset   port1, #$02, L1843      ; 
            andm    t2_csr, #$fe            ; 
L1843       brset   port1, #$04, L1844      ; 
            andm    t2_csr, #$fb            ; 
L1844       ldd     t1t2_clk                ;                                 
            addd    #$0016                  ;                               
            std     t2_outCmpWr             ;                                    
            bsr     actDeact23              ;                                   
            jsr     schedDeact23            ;                                     

            ;-------
            ; Exit
            ;-------
L1845       rti                             ;                             
                                                                   ; 

;******************************************************************
;
; Enable injector activation bit for injector #1 or #4
; and calculate the corresponding injector deactivation time
;
;
;
;******************************************************************
actDeact14  ldd     t1_outCmpWr              ; 
            addd    injPw                    ; d = t1_outCmpWr + injPw                             
            brset   newInjToAct, #$04, L1847 ; Branch if inj #4 needs activation

            ;--------------------------------
            ; Injector #1 needs activation
            ;--------------------------------
            andm    t1_csr, #$fe            ; Reset injector #1 bit                                 
            std     inj1_offT               ; inj1_offT = t1_outCmpWr + injPw                             
            bra     L1848                   ; Bail                             

            ;--------------------------------
            ; Injector #4 needs activation
            ;--------------------------------
L1847       andm    t2_csr, #$df            ; Reset injector #4 bit                                 
            std     inj4_offT               ; inj4_offT = t1_outCmpWr + injPw                             
L1848       rts                             ;                             



;******************************************************************
;
; Enable injector activation bit for injector #1 or #4
; and calculate the corresponding injector deactivation time
;
;
;
;******************************************************************
actDeact23  ldd     t2_outCmpWr              ;                                                        
            addd    injPw                     ; d = t1_outCmpWr + injPw                                                        
            brset   newInjToAct, #$08, L1850  ;                                                        

            ;--------------------------------
            ; Injector #3 needs activation
            ;--------------------------------
            andm    t2_csr, #$fe            ; Reset injector #3 bit (enable output compare interrupt???)                                   
            std     inj3_offT               ;                                                       
            bra     L1851                   ;                                                       

            ;--------------------------------
            ; Injector #2 needs activation
            ;--------------------------------
L1850       andm    t2_csr, #$fb            ; Reset injector #2 bit                                    
            std     inj2_offT               ;                                                       
L1851       rts                             ;                                                      



;******************************************************************
;
; Table used to determine which cylinder/injector the current 
; CAS interrupt corresponds to. The table contains injector bit masks 
;
;
; t_cylMask[casCylIndex] -> cylinder numbers: 2 1 3 4                            
;
;
;******************************************************************
t_cylMask       .byte   $08, $01, $02, $04



;******************************************************************
;
; Output compare interrupt1 
;
; Triggered by injector #1 and #4 activation/deactivation
;
;
;******************************************************************
outCompInt1 ldaa    t1_csr                  ; Ack interrupt?                              
            ldd     t1_outCmpWr             ; 
            std     t1_outCmpWr             ; Flush the output compare value that triggered the current interrupt??? 
            jsr     schedDeact14            ; Schedule deactivation time

            ;------------------------------------------
            ; Branch to execute rest of subroutine...
            ;------------------------------------------
            bra     L1855                                                 



;******************************************************************
;
; Output compare interrupt2
;
; Triggered by injector #2 and #3 activation/deactivation
;
;
;******************************************************************
outCompInt2 ldaa    t2_csr                  ; Ack interrupt?                              
            ldd     t2_outCmpWr             ; 
            std     t2_outCmpWr             ; Flush the output compare value that triggered the current interrupt???                       
            jsr     schedDeact23            ; Schedule deactivation time                                                           

            ;------------------------------------------
            ; Perform injector testing and update 
            ; simultaneous injection mode if required
            ;------------------------------------------
L1855       jsr     injUpdate0              ;                              
            rti                             ;                             



;******************************************************************
;
; Schedule injector #1 and #4 deactivation 
; time interrupt if necessary
;
;
;******************************************************************
            ;-----------------------------------
            ; Update oldInjToAct and injToAct
            ;-----------------------------------
schedDeact14 ldaa   injToAct                ; a = injToAct                             
            staa    oldInjToAct             ; oldInjToAct = old injToAct
            brclr   port2, #$02, L1857      ; Branch if injector #1 is activated                              
            anda    #$fe                    ; Reset injector #1 bit                            
L1857       brclr   port1, #$08, L1858      ; Branch if injector #4 is activated                              
            anda    #$fb                    ; Reset injector #4 bit                             
L1858       staa    injToAct                ; Update injToAct
                               
            ;--------------------------------------------------------------------------
            ; Clear sInjPw if injectors from both banks are activated (1 or 4 and 2 or 3)
            ;--------------------------------------------------------------------------
            brclr   oldInjToAct, #$05, L1860 ; Branch if both inj #1 and #4 are not activated
            brclr   port1, #$04, L1859       ; inj #1 or #4 activated, branch if #2 activated (sim injection on)                               
            brset   port1, #$02, L1860       ; Branch if #3 not activated (sim injection off                                
L1859       clr     sInjPw                   ; clear sInjPw and sInjPw+1                             
            clr     sInjPw+1                 ;                              

            ;----------------------------------
            ; Find which of #1 or #4 is active
            ;----------------------------------
L1860       brclr   port2, #$02, L1861      ; Branch if inj #1 activated                                
            brset   port1, #$08, L1866      ; Bail if inj #4 is also deactivated (none activated)                               
            bra     L1862                   ; Only inj #4 activated, branch to deactivate it                            

            ;------------------------------
            ; Inj #1 activated, check #4
            ;------------------------------
L1861       brset   port1, #$08, L1864      ; Branch if #4 deactivated                              

            ;--------------------------
            ; Inj #1 and #4 activated
            ;--------------------------
            ldx     #inj1_offT              ; x points to injectors deactivation time table                              
            jsr     injRemTime              ; Compute injection remaining time for #1 and #4, a = remTime1, b = remTime4                              
            sba                             ; a = remTime1 - remTime4                            
            bcs     L1863                   ; Branch if remTime1 < remTime4                        
                 
            ;---------------------------------------------------------------------------------
            ; Inj #1 and #4 are activated and remTime1 >= remTime4
            ;
            ; This would mean we are in #1 combustion cycle. In that case, we would 
            ; deactivate inj #4 first (since it has been injecting for a long time by now) 
            ; and eventually inj #1 (which has just started injecting)
            ;
            ; Branch to disable only inj #4 if remTime1 - remTime4 > 1.024ms
            ;---------------------------------------------------------------------------------
            cmpa    #$04                    ;                              
            bhi     L1862                   ; Branch if remTime1-remTime4 > 4 (1.024ms)

            ;--------------------------------------------------------------------
            ; remTime1-remTime4 <= 4 (1.024ms). This means both injectors will 
            ; be disabled at about the same time, just deactivate both
            ; of them at that time...
            ;
            ; Disable the activation bit for inj. #1 and #4 (two lines below)
            ; and use inj. #4 deactivation time
            ;--------------------------------------------------------------------
            orm     t1_csr, #$01            ; Disable the activation bit for inj. #1

            ;-----------------------------------------
            ; Disable the activation bit for inj. #4 
            ; and load deactivation time in d
            ;-----------------------------------------
L1862       orm     t2_csr, #$20            ; Disable the activation bit for inj. #4
            ldd     inj4_offT               ; d = inj4_offT, injector #4 deactivation time                                   
            bra     L1865                   ; Branch to schedule deactivation interrupt                             

            ;--------------------------------------------------------------------------------------
            ; Inj #1 and #4 are activated and remTime1 < remTime4
            ; This would mean we are in #4 combustion cycle. In that case,
            ;--------------------------------------------------------------------------------------
L1863       nega                            ; make result positive, a = remTime4 - remTime1
            cmpa    #$04                    ;                             
            bhi     L1864                   ; Branch if remTime4 - remTime1 > 4 (1.024ms)                             

            ;--------------------------------------------------------------------
            ; remTime4-remTime1 <= 4 (1.024ms). This means both injectors will 
            ; be disabled at about the same time, just deactivate both
            ; of them at that time???
            ;
            ; Disable the activation bit for inj. #4 and #1 (two lines below)
            ; and use inj. #1 deactivation time
            ;--------------------------------------------------------------------
            orm     t2_csr, #$20            ; Disable the activation bit for inj. #4

            ;-----------------------------------------
            ; Disable the activation bit for inj. #1
            ; and load deactivation time in d
            ;-----------------------------------------
L1864       orm     t1_csr, #$01            ; Disable the activation bit for inj. #1
            ldd     inj1_offT               ; d = inj1_offT, i.e. inj #1 deactivation time  
                                            
            ;--------------------------------------------------------------------------
            ; Validate deactivation time and write to timer 1 output compare register
            ;--------------------------------------------------------------------------
L1865       bsr     validDeactT             ; Validate deactivation time                              
            ldx     t1_csr                  ; Read t1_csr and  t1t2_clk??? sequence to follow I assume but it is different from schedDeact23???
            std     t1_outCmpWr             ; Write next interrupt time                                    
L1866       rts                             ;                             



;******************************************************************
;
; Schedule injector #2 and #3 deactivation time interrupt
;
; Logic is identical to the actDeact14 subroutine
;
;
;******************************************************************
schedDeact23 ldaa    injToAct               ;                               
            staa    oldInjToAct             ;                              
            brclr   port1, #$04, L1868      ; 
            anda    #$f7                    ; 
L1868       brclr   port1, #$02, L1869      ; 
            anda    #$fd                    ; 
L1869       staa    injToAct                ; 
            brclr   oldInjToAct, #$0a, L1871 ;
            brclr   port1, #$08, L1870      ; 
            brset   port2, #$02, L1871      ; 
L1870       clr     sInjPw                  ; 
            clr     sInjPw+1                ; 
L1871       brclr   port1, #$04, L1872      ; 
            brset   port1, #$02, L1877      ; 
            bra     L1875                   ;  
L1872       brset   port1, #$02, L1873      ; 
            ldx     #$00ab                  ;  
            bsr     injRemTime              ;  
            sba                             ;  
            bcs     L1874                   ;  
            cmpa    #$04                    ;  
            bhi     L1873                   ;  
            orm     t2_csr, #$01            ; 
L1873       orm     t2_csr, #$04            ; 
            ldd     inj2_offT               ;  
            bra     L1876                   ;  
L1874       nega                            ;  
            cmpa    #$04                    ;  
            bhi     L1875                   ;  
            orm     t2_csr, #$04            ; 
L1875       orm     t2_csr, #$01            ; 
            ldd     inj3_offT               ;  

            ;--------------------------------------------------------------------------
            ; Validate deactivation time and write to timer 2 output compare register
            ; sequence is different compared to schedDeact14?????? (and the t1 and t2
            ; control registers are also different????)
            ;--------------------------------------------------------------------------
L1876       bsr     validDeactT                                                 
            std     t2_outCmpWr                                                 
L1877       rts                                                          



;******************************************************************
;
; Check injector deactivation time for validity
;
; Input: 
;       d = deactTime = injector deactivation time 
;
;
; Output:
;       d = deactTime or current time + 20us if deactTime>61ms
;
;******************************************************************
validDeactT std     temp8                   ; temp8 = deactTime                               
            subd    #$0014                  ; d = deactTime - $14   (20us)                              
            subd    t1t2_clk                ; remTime = d = deactTime - $14 - t1t2_clk (remaining time until deactivation - 20us)                                
            cmpd    #$ee00                  ;                               
            ldd     temp8                   ; d = deactTime                              
            bcs     L1879                   ; Branch if remTime < $ee00 (61ms)                             

            ;--------------------------------------------- 
            ; Remaining time too high, deactivate in 20us
            ;--------------------------------------------- 
            ldd     t1t2_clk                ; d = t1t2_clk                                 
            addd    #$0014                  ; d = t1t2_clk + 20us                              
L1879       rts                             ;                             



;******************************************************************
;
;  Compute the remainingInjectionTime/256 for injectors #1 and #4 (or #2 and #3)
;  remaining time might be measured from the most recent CAS falling edge since
;  that is what last_t1t2_clk contains... However the function might also be called 
;  just after last_t1t2_clk has been updated... but not always??? In any case, the 
;  difference between the two remaining times is the most important...
;
; Input: 
;       x: points to inj1_offT or inj3_offT (injector deactivation time table)
;
; Output:
;       a = 0 if inj #1 (or #2) remaining injection time > 61ms  else  remaining injection time/256
;       b = 0 if inj #4 (or #3) remaining injection time > 61ms  else  remaining injection time/256
;
; Basically a and b are the remainingActivationTime/256
; or 0 if it doesn't make sense (i.e. > 61ms)
;
;******************************************************************
injRemTime  ldaa    $00,x                   ; a = inj1_offT/256
            suba    last_t1t2_clk           ; a = inj1_offT - last_t1t2_clk
            cmpa    #$ee                    ;                             
            bcs     L1881                   ; Branch if inj1_offT - last_t1t2_clk <$ee (61ms)
            clra                            ; a = 0                            

L1881       ldab    $04,x                   ; b = inj4_offT/256
            subb    last_t1t2_clk           ; b = inj4_offT/256 - last_t1t2_clk
            cmpb    #$ee                    ;                            
            bcs     L1882                   ; Branch if inj1_offT - last_t1t2_clk <$ee (61ms)
            clrb                            ; b = 0                            
L1882       rts                             ;                             



;******************************************************************
;
; Called on every injector activation/deactivation (output compare)
;
; Tests injector feedback bit if time has come and 
; perform simultaneous injection activation/deactivation if
; required
;
;
;******************************************************************
            ;------------------------------------------------------------------
            ; Check whether we should test the injectors for proper operation
            ;------------------------------------------------------------------
injUpdate0  ldaa    injToTest               ; a = injToTest                               
            cmpa    oldInjToAct             ;                                    
            bne     L1885                   ; Bail if injToTest != oldInjToAct, i.e. the injector to test was not the one and only one activated
            brset   injToAct, #$0f, L1885   ; Bail if any injector currently activated          
                                   
            ;--------------------------------------------------------------------------------
            ; At this point, we know that the current injector to test was
            ; active in the past (oldInjToAct) and that it is not active anymore
            ; (injToAct). Basically, we know that the injector to test was just 
            ; deactivated and no other injector is currently active. 
            ;
            ; port4.7 might be loaded on the falling edge of the injector driving current???
            ;--------------------------------------------------------------------------------
            ;------------------------------------------------------------------
            ; Check feedback flag to know if injector is working correctly???
            ;------------------------------------------------------------------
            brclr   port4, #$80, L1884      ; Branch if injector flag shows it is OK?                                
            orm     injBad, #$01            ; Set bit indicating injectors is bad?                                   
            bra     L1885                   ; Branch to rest of code, we will continue testing the same injector.                             

            ;--------------------------------------------------------------
            ; Injector is OK, reset injBad flag and go to next injToTest
            ;--------------------------------------------------------------
L1884       asla                            ; a = injToTest<<1, go to next injector to test
            andm    injBad, #$fe            ; Reset bit indicating injectors is bad?                                

            ;-------------------
            ; Update injToTest
            ;-------------------
L1885       anda    #$0f                    ; Keep only 4 bits, 4 injectors to test
            bne     L1886                   ; Branch if any injector bit left                             
            ldaa    #$01                    ; Nothing left, restart testing with injector at bit 0                             
L1886       staa    injToTest               ; Update injToTest
            ;-----------------------------------
            ; Code continues in function below......
            ;-----------------------------------
            ;;;;; bra  simInject





;******************************************************************
;
; Simultaneous injection code called every 10ms from real time
; interrupt or from above code continuation. sInjPw is cleared
; if sim. injection is actually scheduled such that even if it 
; is called from multiple places, sim. injection will only happen
; once every time sInjPw is re-loaded...
;
;
;******************************************************************
            ;----------------------------------------------------------------------------
            ; Bail out of function if any injectors are set in injToAct 
            ; (rest of function is for simultaneous injection and all bit should be 0?)
            ;----------------------------------------------------------------------------
simInject   brset   injToAct, #$0f, L1897   ; branch if any injector bit set
                                 
            ;-------------------------------------------------------
            ; All injectors are currently off, we can therefore
            ; proceed with simultaneous injection if sInjPw >256us
            ;
            ; Update injPw from sInjPw if larger than 256us
            ;-------------------------------------------------------
            ldd     sInjPw                  ; d = sInjPw
            tsta                            ;                             
            beq     L1897                   ; Bail of subroutine if sInjPw/256 = 0 (sInjPw<256us), too small....
            clr     sInjPw                  ;                              
            clr     sInjPw+1                ; clear sInjPw                              
            bsr     addDeadtime             ; Add deadTime                                   
            std     injPw                   ; injPw = sInjPw + deatTime
                                         
            ;------------------------------------------------------------
            ; Round injPw up to specific values if within some ranges, 
            ; Not quite sure why but I think that when the 
            ; injection time becomes small, injection time is less 
            ; predictable or simply non linear in some ranges... In
            ; any case, since these times include the deadtime, they are
            ; quite small..., not sure any fuel will actually come out?
            ;
            ;          injPw <= 840us  -> 840us
            ;  840us < injPw <= 960us  -> no change
            ;  960us < injPw <= 1100us -> 1100us
            ; 1100us < injPw           -> no change
            ;------------------------------------------------------------
            ldd     #$0348                  ; 
            cmpd1   injPw                   ;                              
            bcc     L1888                   ; Branch to use $0348 if injPw <= $0348 (840us)                           
            ldd     #$03c0                  ; 
            cmpd1   injPw                   ;                              
            bcc     L1889                   ; Branch to use injPw if injPw <= $03c0 (960us)                              
            ldd     #$044c                  ; 
            cmpd1   injPw                   ;                              
            bcs     L1889                   ; Branch to use injPw if injPw > $044c (1100us)                             
L1888       std     injPw                   ;                              

            ;------------------------------------------------------
            ; Update newInjToAct, start with all injectors 
            ; active and remove the ones disabled by obd
            ; and the ones corresponding to missing ignition 
            ; signals
            ;------------------------------------------------------
L1889       ldaa    #$0f                      ; All 4 injectors set by default                              
            brset   state3, #$01, L1891       ; Branch if startingToCrank                              
            brclr   coilChkFlags, #$80, L1890 ; Branch if no error found on ignition
            anda    coilChkFlags              ; Disable injectors corresponding to missing ignition
L1890       anda    obdInjCmd                 ; Disable injectors that are off on purpose (OBD)
L1891       staa    newInjToAct               ; Update newInjToAct      
                       
            ;-----------------------------------
            ; Code continues in function below......
            ;-----------------------------------
            ;;;;; bra  schedInjSim




;******************************************************************
;
; Function to schedule interrupts for injectors activation and 
; deactivation in the case of simultaneous injection. Called from 
; main code and from above code continuation...
;
; Simulataneous injection can be either when startingToCrank or
; when starting a cold engine or during acceleration (sInjEnr) 
;
; injPw need to be initialized with the proper value (e.g. sInjPw)
; prior to calling this function
;
;******************************************************************
            ;--------------------
            ; Update last_t1t2_clk
            ;--------------------
schedInjSim ldd     t1t2_clk                ; a = t1t2_clk, current time                                
            staa    last_t1t2_clk           ; last_t1t2_clk = t1t2_clk/256                             

            ;------------------------------------------------------
            ; Schedule interrupt in 2.048ms 
            ;
            ; This might be to revert to previous injector 
            ; settings after 2.048ms ???? t1_outCmpWr
            ; and t2_outCmpWr would need to be triple buffered???
            ;------------------------------------------------------
            adda    #$08                    ; d = t1t2_clk + 8*256 (2.048ms)
            std     t1_outCmpWr             ; Store interrupt time for injector #1 and #4
            std     t2_outCmpWr             ; Store interrupt time for injector #2 and #3

            ;--------------------
            ; Update injToAct
            ;--------------------
            ldaa    newInjToAct             ;                               
            anda    #$3f                    ; Keep only lower 6 bits (6 injectors max?)
            staa    injToAct                ;                              

            ;-------------------------------------------------------------------
            ; Reset bit of t1_csr and t2_csr according to activated injectors
            ;-------------------------------------------------------------------
            ldaa    newInjToAct             ; a = newInjToAct                             
            rora                            ; transfer bit 0 to carry                            
            bcc     L1893                   ; Branch if injector 1 is off                               
            andm    t1_csr, #$fe            ; Injector 1 is activated, reset bit                                 
L1893       rora                            ;                             
            bcc     L1894                   ; Branch if injector 3 is off                             
            andm    t2_csr, #$fe            ; Injector 3 is activated, reset bit
L1894       rora                            ;                             
            bcc     L1895                   ; Branch if injector 4 is off                             
            andm    t2_csr, #$df            ; Injector 4 is activated, reset bit
L1895       rora                            ;                             
            bcc     L1896                   ; Branch if injector 2 is off                             
            andm    t2_csr, #$fb            ; Injector 2 is activated, reset bit

            ;-------------------------------------------------------------
            ; Schedule interrupts to activate specified injectors in 10us
            ;-------------------------------------------------------------
L1896       ldd     t1t2_clk                ; d = t1t2_clk
            addd    #$000a                  ; d = t1t2_clk + 10us
            std     t1_outCmpWr             ; Turn injector on in 10us.                                     
            std     t2_outCmpWr             ; Turn injector on in 10us.                                     

            ;-------------------------------------------------------------
            ; Compute and store deactivation time 
            ; (common to all injectors when using simultaneous injection)
            ;-------------------------------------------------------------
            addd    injPw                   ; d = t1t2_clk + 10us + injPw
            std     inj1_offT               ;                              
            std     inj3_offT               ;                              
            std     inj4_offT               ;                              
            std     inj2_offT               ;                              

            ;------------------------------------------------------------------------
            ; Schedule interrupts to deactivate all injectors at the specified time
            ;------------------------------------------------------------------------
            orm     t1_csr, #$01            ; Set bit for injector 1
            orm     t2_csr, #$25            ; Set bits for injector 3 4 and 2
            std     t1_outCmpWr             ; Turn injector off at that time?
            std     t2_outCmpWr             ; Turn injector off at that time?                                 
L1897       rts                                                          



;******************************************************************
;
;
; Injectors, add $18*deadTime to injPw (in d)
;
; deadTime is in increment of 24us and injPw in increment of 1us
;
;
;******************************************************************
addDeadtime std     temp8                   ; temp8 = injPw                               
            ldaa    deadTime                ; a = deadTime                                
            ldab    #$18                    ; b = $18                            
            mul                             ; d = $18*deadTime                          
            addd    temp8                   ; d = injPw + $18*deadTime                              
            bcc     L1899                   ; Branch if no overflow                             
            ldaa    #$ff                    ; Use max of ~$ff00 (65.3ms)                           
L1899       rts                             ;                             



;******************************************************************
;
; Input capture interrupt 2
;
; This interrupt is triggered whenever the 
; airflow sensor emits one pulse
;
;******************************************************************
inCaptInt2  ldaa    t2_csr                  ; ack/reset interrupt/timer control ???
            bsr     masProc                                                 
            rti                                                          



;******************************************************************
;
; Mas airflow pulse accumulator subroutine 
;
; Called from interrupt and code (polling)
;      
; Assumptions: t2_csr.1 controls the input capture trigger edge 
;              polarity. This would imply (from mafraw calculations)
;              that the airflow sensor pulse frequency is 
;              divided by two by the ECU circuitry. In that case, 
;              counting edges (changing polarity through t2_csr.1 
;              on every interrupt) would correspond to counting 
;              airflow sensor pulses.
;
; Under low airflow, it is called on every rising and falling 
; edge of incoming signal (airflow sensor frequency/2) and it is
; therefore called on every airflow sensor pulse.
;
; When large airflow is detected or when the time between each
; interrupt becomes small, it is called only once for every 2 
; airflow sensor pulses (called scaling) in order to reduce 
; the number of interrupts per sec (CPU load). 
;
; airCntNew0:airCntNew1 is increased by airQuantum = $9c on every 
; call (rising and falling edge) or by 2*airQuantum if we are 
; scaling.
;
;******************************************************************
            ;----------------------------------------------
            ; Compute t2_diff8 and update t2_lastMas
            ;----------------------------------------------
masProc     ldd     t2_inCapt               ; Read current input capture timer value                                 
            subd    t2_lastMas              ; D = t2_inCapt-t2_lastMas
            ldx     #T200_mas               ;                                                                             
            jsr     masFunc1                ; D = (t2_inCapt-t2_lastMas)/8 with timer based rounding???                                                              
            std     t2_diff8                ; t2_diff8 = (t2_inCapt-t2_lastMas)/8 with timer based rounding (see masFunc1)
            ldd     t2_inCapt               ;                                                                            
            std     t2_lastMas              ; t2_lastMas = t2_inCapt

            ;-----------------------------------
            ; Re-init counter used in masFunc1
            ;-----------------------------------
            ldaa    #$1a                    ; 130ms                                                                           
            staa    T200_mas                ;                                                                            

            ;--------------------------------------
            ; Add scaled airQuantum to airCntNew0
            ;--------------------------------------
            clra                              ;                                                                           
            ldab    airQuantum                ; d = airQuantum
            brclr   masCasFlags, #$80, L1902  ; Branch if no scaling
            asld                              ; scale d = 2*airQuantum
L1902       addd    airCntNew0                ; d = airCntNew0 + airQuantum
            bne     L1903                     ; Branch if result not null                                                                           
            incb                              ; Result is null, use min of 1                                                                     
L1903       std     airCntNew0                ; Store airCntNew0 = max(airCntNew0 + airQuantum, 1)                                               

            ;----------------------------------
            ; Re-init airQuantum with #9c
            ;----------------------------------
            ldaa    #$9c                    ;                                                                           
            staa    airQuantum              ; airQuantum = $9C                                                                

            ;----------------------------------
            ; Check if we are using scaling
            ;----------------------------------
            brset   masCasFlags, #$80, L1905      ; branch if scaling by two                                                    


            ;-----------------------------------------------------------
            ; We are not scaling, check if that needs to change
            ; Either if airVol is high (i.e. airVol > $6b, corresponds
            ; to about 0.4gramOfAir) or if airflow sensor pulse
            ; frequency is high (>500Hz)
            ;-----------------------------------------------------------
            ldaa    airVol                  ;                                                                             
            cmpa    #$6b                    ;                                                                            
            ldd     t2_diff8                ; preload d = t2_diff8                                                                                       
            bhi     L1904                   ; branch if airVol > $6b        
            cmpd    #$00fa                  ; $fa*8/1MHz = 2ms -> 500Hz
            bcc     L1907                   ; Branch if t2_diff8 > $00fa (freq<500Hz)  

            ;----------------------------------------------------------------------------
            ; At this point we were not scaling by 2 but airVol>$6b or t2_diff8 < $00fa
            ; (freq>500Hz) we need to activate scaling
            ;----------------------------------------------------------------------------
L1904       asld                            ; t2_diff8 = t2_diff8*2                                                                        
            orm     masCasFlags, #$80       ; set scaling bit
            bra     L1906                   ; Go to rest of code                                                                                            

            ;------------------------------------------------------
            ; We were scaling by 2, check if that needs to change 
            ;------------------------------------------------------
L1905       ldaa    airVol                  ;                                                                                              
            cmpa    #$6b                    ;                                                                                            
            ldd     t2_diff8                ; preload d=t2_diff8                                                                                              
            bhi     L1906                   ; branch if airVol>$6b                                                                        
            cmpd    #$0271                  ; airVol<=$6B                                                                                             
            bcs     L1906                   ; Branch if t2_diff8 < $0271                                                                    

            ;----------------------------------------------------------------------------
            ; At this point, we were scaling by 2 but airVol<=$6B and t2_diff8 > $271
            ; we can therefore go back to no scaling
            ;----------------------------------------------------------------------------
            lsrd                            ; t2_diff8 = t2_diff8/2                                                                        
            andm    masCasFlags, #$7f       ; reset scaling bit

            ;----------------------------------
            ; Update t2_diff8
            ;----------------------------------
L1906       std     t2_diff8                ; store new value                                                                               

            ;-------------------------------------------------------------------------------
            ; Change the interrupt trigger polarity if we are not scaling since in that case
            ; we want interrupts on both rising and falling edges of the incomming signal pulse
            ; In case of scaling by 2, the polarity remains the same on every interrupt and
            ; we therefore only receive interrupts on every two edges...
            ;-------------------------------------------------------------------------------
L1907       brset   masCasFlags, #$80, L1908 ; branch if we are scaling
            ldaa    t2_csr                  ; We are not scaling, switch edge trigger polarity
            eora    #$02                    ; switch edge trigger polarity
            staa    t2_csr                  ;                                                                                              

            ;----------------------------
            ; Restart timer and return
            ;----------------------------
L1908       ldaa    #$0c                                                 
            staa    T40_mas                                                 
            rts                                                          



;******************************************************************
;
; Divide the time between airflow sensor pulse by 8 with a 
; timer based rounding???
;
; Input is the time between two airflow sensor pulse in D
;
; Input is also X which points to the timer T200_mas which is init 
; to 130ms on every airflow sensor pulse receied.
;
; output: D = D/8 with timer based rounding if timer not expired (not 0)
;         D = 3FFF otherwise
;
;******************************************************************
masFunc1    lsrd                            ;                                                                       
            lsrd                            ;                                                                       
            lsrd                            ; d = diff/8                                                      
            std     temp8                   ; temp8 = diff/8                                                                        
            ldaa    $00,x                   ; a = timer value 
            tsta                            ; why test, we just loaded in A??????                                   
            bne     L1910                   ; Branch if counter not zero                                                                       

            ;-------------------------------
            ; Timer expired, return max value
            ;-------------------------------
            ldd     #$3fff                  ; If timer expired, return $3fff
            bra     L1913                   ;                                                                                           

            ;-----------------------------------------------
            ; Timer not expired, calculate value to return
            ; based on timeLeft (in ms)
            ;
            ;  0 <= timeLeft < 50   -> diff/8 | $2000
            ;
            ; 50 <= timeLeft < 80
            ;      $diff/8 <  $1000 -> diff/8 | $2000
            ;      $diff/8 >= $1000 -> diff/8
            ;
            ; 80 <= timeLeft < 130  -> diff/8
            ;
            ; I think this is basically some kind of round-up
            ; of the time between airflow sensor pulse when 
            ; the frequency is low. timeLeft between 0ms and 50ms
            ; correspond to a time between airflow pulse of 
            ; between 130ms to 80ms, which correspond to a 
            ; frequency of 7.7Hz to 20Hz. By setting value bit
            ; $2000, we are basically making sure the returned
            ; value corresponds to at least 65ms (15Hz), 
            ; assuming a 1MHz clock ($2000*8/1000000)
            ;-----------------------------------------------
L1910       cmpa    #$10                    ;                             
            bcc     L1912                   ; Branch if time left >=80ms (16/200Hz), return value as is                           
            cmpa    #$0a                    ;                             
            bcs     L1911                   ; Branch if time left <50ms (10/200Hz)
            brset   temp8, #$10, L1912      ; Timer is between 50ms<= timer <80ms, branch if diff/8 >= $1000 (value already big enough?, no need to set $2000...)                             
L1911       orm     temp8, #$20             ; set value bit $2000 (add that much to diff/8???)                                
L1912       ldd     temp8                   ; Load and return value                              
L1913       rts                             ;                             




;******************************************************************
;
;
; Real time Interrupt subroutine 
; Frequency: 801.28Hz (see rti_freq)
;
;
;******************************************************************
realTimeInt ldaa    rti_ctl                 ;                                
            ldaa    rti_freq                ;                                 
L1914b      inc     rtiCnt                  ; Increment real time interrupt counter

            ;-----------------------------------------------------
            ; Check if key is in start and cas signal is active
            ;-----------------------------------------------------
            brset   port3, #$40, L1915      ; Bail if key is not is start
            brset   port5, #$01, L1915      ; Bail if cas signal is low 

            ;------------------------------------------
            ; key is in start and cas signal is active
            ; reset a few things
            ;------------------------------------------
            clra                            ;                             
            clrb                            ;                             
            staa    casFlags0               ; casFlags0 = 0                              
            staa    enerFlags               ; enerFlags = 0                             
            std     ignFallRelTime0         ; ignFallRelTime0 = 0
                                         
            ;------------------------------------------------------------------------------------
            ; Key is in start and cas signal is active
            ; If no cas interrupt is pending, enable the current coil bit  
            ; and schedule an immediat output compare interrupt to energize it. 
            ;
            ; Basically this makes sure the coil is energized for the whole CAS pulse
            ; during start of crank/cranking...
            ;------------------------------------------------------------------------------------
            brset   t1_csr, #$80, L1915     ; Branch if cas interrupt is pending?                                
            ldaa    tdcMask0                ; a = $02 or $04                             
            asla                            ; a = $04 or $08                            
            coma                            ; a = ~($04 or $08)                            
            anda    t3_csr0                 ; reset that bit, i.e. energize that coil at scheduled time
            staa    t3_csr0                 ; update t3_csr0                              
            ldx     t3_clock1               ;                                    
            inx                             ;                             
            inx                             ; x = t3_clock1 + 2, basically in a few microsec                           
            stx     t3_outCmpWr             ; Schedule interrupt for "now" on first output compare register

            ;------------------------------------------------
            ; increament rtiCnt48 and loop from 47 to 0...
            ; If we loop to 0, also reset the egr and boost 
            ; control solenoid output, i.e. this is the start
            ; of the pulswidth modulation cycle
            ;------------------------------------------------
L1915       ldab    rtiCnt48                ; b = old rtiCnt48
            incb                            ;                             
            stab    rtiCnt48                ; rtiCnt48 = old rtiCnt48 + 1                                
            cmpb    #$30                    ;                             
            bcs     L1916                   ; Branch if  old rtiCnt48 + 1 < 48
            clrb                            ; b = 0                            
            stab    rtiCnt48                ; rtiCnt48 = 0                                                                                                                                              
            andm    port5, #$d7             ; When rtiCnt48 reaches 48, reset port5.5 and port5.3 

            ;-----------------------------------------------------------
            ; Set the egr solenoid output if time has come (duty cycle)
            ;-----------------------------------------------------------
L1916       cmpb    egrDuty                 ; 
            bcs     L1917                   ; Branch if rtiCnt48 < egrDuty                                                                                                                                           
            orm     port5, #$08             ; Set the egr solenoid                                                                                            

            ;-------------------------------------------------------------------------
            ; Set the boost control solenoid output if time has come (duty cycle)
            ;-------------------------------------------------------------------------
L1917       cmpb    bcsDuty                 ; Boost control solenoid duty cycle, second threshold?                                                                                         
            bcs     L1918                   ; Branch if rtiCnt48 < egrDuty                                                                                                                                           
            orm     port5, #$20             ; 
                                                                                                                                                           
            ;-------------------------------------------
            ; At this point b = new value of rtiCnt48
            ;
            ; Update boost gauge output at 801.28Hz
            ;-------------------------------------------
L1918       ldaa    bGaugeODuty             ; a = bGaugeODuty ("off-duty" cycle)
            cmpb    #$18                    ; 
            bcs     L1919                   ; branch if rtiCnt48 < 24                                                                     
            subb    #$18                    ; b = rtiCnt48-24 (we only need a value from 0 to 24 here, use 24 to 48 as a new 0 to 24...)
            brclr   state3, #$10, L1919     ; Branch if notRotating clear                                                                           
            inca                            ; Engine not rotating, a = bGaugeODuty+1 (why?, wiggle the needle a bit?)                                                                        
L1919       tstb                            ; 
            bne     L1920                   ; Branch if rtiCnt48 != 0                                                                          
            andm    port6, #$fb             ; rtiCnt48=0, start with boost gauge output = 0 at the beginning of cycle
L1920       cba                             ; 
            bhi     L1921                   ; Branch if bGaugeODuty > rtiCnt48                                                                          
            orm     port6, #$04             ; Change boost gauge output to 1 when rtiCnt48 >= bGaugeODuty
L1921       .equ    $                       ;   

            ;-----------------------------------------------------
            ; Branch to next section at 400Hz if time has come
            ;-----------------------------------------------------
L1921b      brclr   rtiCnt, #$01, L1922     ; Branch once out of two times
            rti                             ;                                                                       




;******************************************************************
;
;
; Code executed at 1/2 rate (~400Hz)
;
;
;******************************************************************
            ;--------------------------------------------------------------------------------
            ; Although we are still in interrupt code , we will re-enable interrupts
            ; for the important ones (the coil and cas interrupts) until we get out of here
            ;--------------------------------------------------------------------------------
L1922       andm    t1_csr, #$f7             ; reset 0000 1000, disable interrupts from injector 1???
            andm    t2_csr, #$e7             ; reset 0001 1000 disable interrupts from injectors 2,3,4 and airflow sensor???
            andm    rti_ctl, #$bf            ; disable interrupts from real time interrupt (we are already in it and it is not re-entrant...)
            andm    sci_scr, #$ef            ; Disable serial port rx interrupt 
            cli                              ; Re-enable all interrupts that were not disabled                                                                                         
                                                                    
            ;--------------------------------------------------------------------------------
            ; Speed sensor update:
            ; At 100km/h, reed switch sensor will generate ~reedHz=69Hz square wave (~40cm/cycle)
            ; vssValue will reflect the number of interrupt calls during one complete cycle,
            ; i.e. the quare wave period measured in 1/400sec
            ;--------------------------------------------------------------------------------
            ldaa    vssCnt1                 ;                                                                                                                       
            beq     L1923                   ;                                                                                                                       
            deca                            ;                                                                                                                      
            staa    vssCnt1                 ;                                                                                                                       
L1923       ldaa    vssCnt2                 ;                                                                                                                       
            beq     L1924                   ;                                                                                                                       
            deca                            ;                                                                                                                      
            staa    vssCnt2                 ;                                                                                                                       
L1924       ldab    rtiReedFlags            ;                                                                                                                       
            rol     rtiReedFlags            ;                                                                                                                       
            ldaa    port1                   ;                                                                                                                        
            rola                            ;                                                                                                                      
            ror     rtiReedFlags            ; rtiReedFlags.7 contains latest REED switch value                                                                             
            eorb    rtiReedFlags            ; B.7 = 1 if reed switch value changed                                                                                  
            bmi     L1925                   ; Branch if Reed switch value changed                                                                                   
            ldaa    vssCnt2                 ; No change in reed switch value                                                                                        
            bne     L1927                   ; branch if C5 not yet 0                                                                                                
            ldaa    #$e2                    ;                                                                                                                       
            bra     L1926                   ; vssCnt reached 0, prepare to store E2 in speedSensor (lowest possible speed)                                          

            ;-----------------------------------
            ; Reed switch value changed, 
            ; update speedSensor pulse counter
            ;-----------------------------------
L1925       ldab    #$c8                    ;                                                                                                                                                      
            stab    vssCnt1                 ; Re-initialize vssSlowCnt                                                                                                                              
            brset   rtiReedFlags, #$80, L1927 ; branch if new value is 1                                                                                                                               
            ldaa    #$e2                    ; Reed switch value just changed to 0..                                                                                                                
            suba    vssCnt2                 ; A = # pulses counted for the last interval                                                                                                            
            ldab    #$e2                    ;                                                                                                                                                      
            stab    vssCnt2                 ; Re-Initialize vssCnt                                                                                                                                  
L1926       staa    vss                     ; Store new speedSensor value (number of times interupt was called during an entire pulse (falling edge to falling edge)                                

L1927       .equ    $

L1927b      brclr   rtiCnt, #$03, L1928     ; branch to other stuff at a frequency "real time int freq."/4                                                                                                       
            jmp     L1950                   ;                                                                                                                                                       

            ;----------------------------------
            ; Code executed at ~200Hz
            ; Read ADC (tpsRaw, battRaw)
            ;----------------------------------
L1928       ldaa    #$0f                    ;                              
            jsr     readAdc1                ;                                 
            cli                             ;                             
            stab    tpsRaw                  ;                               
            ldaa    #$0d                    ;                             
            jsr     readAdc1                ;                                 
            cli                             ;                             
            stab    battRaw                 ;     
            
            ;-------------------------------------------------------------------------------
            ; Decrement 5 down counters at  $be, $bf, $c0, $c1, $c2 
            ;-------------------------------------------------------------------------------
            ldx     #T200_40Hz                                                 
            ldab    #$05                    ; Loop 5 times, $be, $bf, $c0, $c1, $c2
L1929       ldaa    $00,x                                                 
            beq     L1930                   ; branch if counter already 0                              
            dec     $00,x                   ; decrement  one of $be, $bf, $c0, $c1, $c2
L1930       inx                             ; go to next down counter                            
            decb                            ;                             
            bne     L1929                   ; loop                              

            ;------------------------------------------
            ; Check/reset 40Hz counter (T200_40Hz)
            ;------------------------------------------
            ldaa    T200_40Hz                  ;
            bne     L1931                   ; branch if first counter not 0
            orm     T200_40Hz, #$05            ; Reinit counter with 5 (5/200 = 25ms->40Hz)                               
            orm     rtiReedFlags, #$01             ; Set flag at 40 Hz for main loop events 

            ;------------------------------------------
            ; Check T200_cop and change some output on port 6???
            ; Could be some kind of monitoring function:
            ; If main loop goes slower than 20Hz, port6.5 is not
            ; updated and external check could reset the ECU 
            ; in that case (COP)
            ;------------------------------------------
L1931       ldaa    T200_cop                  ;                               
            beq     L1932                   ; Branch if T200_cop reached 0 (meaning main loop is executing at less than 20Hz???)  
            sei                             ;                                               
            ldaa    port6                   ; T200_cop not 0, toggle port6.5                             
            eora    #$20                    ;                             
            staa    port6                   ; Toggle bit 
            cli                                                          

            ;----------------------------------------------------------------------------
            ; Update knock decay:
            ; Decrement knocksum by 1 every time T200s_knock expires and reload timer
            ; T200s_knock with fast or slow decay constant depending on current airVol
            ;----------------------------------------------------------------------------
L1932       ldaa    T200s_knock             ; a = T200s_knock, knock attenuation timer                                        
            beq     L1933                   ; Branch if T200s_knock already expired
            deca                            ; a = T200s_knock-1                                      
            bne     L1935                   ; branch if (T200s_knock-1)!=0 -> store T200s_knock-1 
L1933       sei                             ; at this point T200s_knock = 0 or 1                                                      
            ldaa    knockSum                ; a = knockSum
            beq     L1934                   ; Branch if knockSum = 0
            dec     knockSum                ; knockSum = knockSum-1                                                
L1934       cli                             ;                             
            ldaa    #$78                    ; a=$78 (200Hz/120 = 1.67Hz, slow attenuation)
            brset   knockFlags, #$80, L1935 ; Branch if flag indicate that airVol>$49
            ldaa    #$02                    ; a=$02 (200Hz/2 = 100Hz, fast attenuation)
L1935       staa    T200s_knock             ; store current knock attenuation count                                    

            ;---------------------------------------------------------------
            ; Set iscLowBatt.7 flag if battRaw>=10V (with 0.33V hysteresis) 
            ; else reset it. If battRaw<10V the ISC spindle is not moved...
            ;---------------------------------------------------------------
            ldab    #$8d                    ; b= 10.33V = threshold                                                                           
            ldaa    iscLowBatt              ; a = iscLowBatt                                                                                   
            bpl     L1936                   ; Branch if iscLowBatt.7 already set, meaning battRaw >=10v last time we were here                                                                                  
            ldab    #$88                    ; reduce threshold (hysteresis) to 10.00V                                                                            
L1936       cmpb    battRaw                 ; Check battRaw against 10.00V or 10.33V                                        
            bcs     L1937                   ; branch if battRaw > 10.00 or 10.33V                                        

            ;---------------------------------------------------------------------
            ; battRaw <= 10.00 , clear iscLowBatt and bail, no ISC update
            ;---------------------------------------------------------------------
            clr     iscLowBatt              ; battRaw < 10.00 or 10.33V, clear iscLowBatt                                     
            bra     L1939                   ; Bail

            ;--------------------------------------------------------------------------
            ; battRaw > 10.00 , set iscLowBatt.7 flag and increase iscLowBatt.0.1 counter by 1
            ; If counter < $03 we don't update the ISC spindle (that means that 
            ; battRaw has to be higher than 10.00V for 4/200 sec before we move
            ; the ISC spindle...
            ;--------------------------------------------------------------------------
L1937       oraa    #$80                    ; a = iscLowBatt | $80                             
            inca                            ; a = iscLowBatt | $80 + 1                            
            staa    iscLowBatt              ; iscLowBatt = old iscLowBatt | $80 + 1                              
            cmpa    #$83                    ;                             
            bcs     L1939                   ; Bail if new iscLowBatt.0.1 < $03, no ISC update                             
            ldaa    #$83                    ; Use max of iscLowBatt.0.1 = $03                            
            staa    iscLowBatt              ; iscLowBatt = $83 (flag set and counter = $03)                            

            ;-------------------------
            ; Check ISC complement ???
            ;-------------------------
            ldab    iscPatrnIdx             ; preload b = iscPatrnIdx for later calc                             
            ldaa    iscStepCurr             ; a = iscStepCurr                               
            coma                            ;                             
            anda    #$7f                    ; a = ~iscStepCurr & $7f                             
            cmpa    iscStepCom              ;                                                                                                  
            bne     L1939                   ; branch if complement is incorrect???                                                        

            ;----------------------------------
            ; Complement is OK, continue???
            ;----------------------------------
            ;---------------------------------------------------------------
            ; Section to move the ICS spindle by +/1 step if iscStepCurr != iscStepTarg
            ; this is where it happens...  code executed at 200Hz...
            ;---------------------------------------------------------------
            ldaa    iscStepCurr             ; a = iscStepCurr                                                                                              
            cmpa    iscStepTarg             ; 
            beq     L1939                   ; Bail if current ISC step is what we want (no change needed)
            inca                            ; assume a = iscStepCurr + 1                                                                                           
            incb                            ; assume b = iscPatrnIdx + 1                                                                                           
            bcs     L1938                   ; Branch if iscStepCurr < iscStepTarg (tricky, carry flag is not affected by inca, incb...)
            deca                            ; iscStepCurr >= iscStepTarg, assumption wrong, go in the other direction                                                               
            deca                            ; a = iscStepCurr - 1                                                                                           
            decb                            ;                                                                                            
            decb                            ; b = iscPatrnIdx - 1                                                                                           
L1938       jsr     iscStepComp             ; Update iscStepCurr and iscStepCom with new values
            stab    iscPatrnIdx             ; Update iscPatrnIdx with new value
            ldx     #t_iscPattern           ; x points to t_iscPattern                                                                                              
            andb    #$03                    ; b = new iscPatrnIdx & 00000011                                                                                             
            abx                             ; x points to desired pattern                                                                                            
            sei                             ;                                                                                             
            ldaa    port5                   ; a = port5                                                                                             
            anda    #$3f                    ; a = port5 & 00111111
            adda    $00,x                   ; a = (port5 & 00111111) + t_iscPattern(iscPatrnIdx)
            staa    port5                   ; update port5                                                                                             
            cli                             ;                                                                                             
            ldaa    #$81                    ; a = $81 = 129                                                                                            
            staa    iscLowBatt              ; re-init iscLowBatt to $81
                                                                                                                         
            ;------------------------------------------------------
            ; Section of code to update port2.2 (up to ~L1949)
            ; according to TPS/rpm/airVol/idleSwitch/timer?????
            ;
            ; ????Could be airflow sensor filter reset???
            ;------------------------------------------------------
L1939       brclr   state1, #$10, L1941     ; Branch if notRotating clear

            ;-----------------------------------------
            ; Engine notRotating, clear timer T40s_tps
            ;-----------------------------------------
            clr     T40s_tps                ;                                 
            bra     L1948                   ;                              

            ;----------------------------------------------------------------------------
            ; Engine is at least rotating,
            ; Check whether tpsRaw has increased by more than 1.5% and is between 26%-50% 
            ;----------------------------------------------------------------------------
L1941       clr     tempFlagTps             ; tempFlagTps = 0                                                                                                          
            ldab    tpsRaw                  ; b=tpsRaw                                                                                                        
            ldaa    oldTps1                 ;                                                                                                           
            sba                             ; a = tpsDiff = oldTps1-tpsRaw 
            bls     L1942                   ; branch if new TPS is smaller or equal to old one                                                         
            cmpa    #$04                    ; new tps higher than old one
            bcs     L1944                   ; bail if tpsDiff < 4 (1.5%)                                                                            
            ldaa    #$80                    ; tpsDiff is >=4                                                                                         
            cba                             ; 
            bls     L1944                   ; bail if tps>=50%
            cmpb    #$43                    ; tps <50%
            bcs     L1944                   ; bail if tps<26%                                                                                        
            dec     tempFlagTps             ; at this point tpsDiff and 26%<= tps <50%, set tempFlagTps=$ff                                                                         
            ldaa    #$0e                    ; set T40s_tps to $0e (0.35s) after branch                                                                            
            bra     L1943                   ;                                                                                                          
L1942       cmpb    #$43                    ; New tps smaller than old one
            bcs     L1944                   ; branch if tps < 26%                                  
            clra                            ; tps>26%, clear timer T40s_tps                                       
L1943       staa    T40s_tps                ;                                                             

            ;-----------------------------------------------------------------
            ; At this point b=tpsRaw and
            ; if TPS has increased by more than 1.5% and new value is between 26% and 50%
            ;    T40s_tps = $0e and tempFlagTps = $ff 
            ; else
            ;     tempFlagTps = $00
            ;     if new TPS<26%
            ;        previous T40s_tps is reset to 0
            ;-----------------------------------------------------------------
L1944       ldaa    tempFlagTps             ;                                                                                                           
            bmi     L1947                   ; Branch if tempFlagTps=FF (TPS increased to between 26% and 50%)                                     
            cmpb    #$43                    ; 
            bcc     L1945                   ; branch if tps>= 26%                                                                                       
            ldaa    T40s_tps                ; tps<26%                                                                                                          
            bne     L1947                   ; Branch if timer not expired                                                                                                          
            cmpb    #$31                    ; tps<26% and timer expired
            bcc     L1945                   ; branch if tps>=19%                                                                                        
            cmpb    #$0a                    ; tps<19% and timer expired
            bcc     L1947                   ; branch if TPS>=4%                                                                                         
                                            ; tps<4% and timer expired

            ;---------------------------------------------------------------------
            ; no TPS increase to 26% and 50%
            ; and tps>=26%
            ;     or 19%<=tps<26% and timer expired
            ;     or tps<4% and timer expired
            ; ......
            ;---------------------------------------------------------------------
L1945       ldaa    rpm31                   ;                                                                                                                                                 
            cmpa    #$20                    ; 1000rpm
            bcs     L1946                   ; branch if rpm<1000                                                                                                                             
            ldaa    airVol                  ; rpm>=1000                                                                                                                                                 
            cmpa    #$40                    ;                                                                                                                                                
            bcc     L1948                   ; branch if airVol >= $40                                                                                                                         
L1946       ldaa    port3                   ;                                                                                                                                                 
            bpl     L1948                   ; branch if idle switch off                                                                                                                       

            ;---------------------------------------------------------------------
            ; Reset port2.2 (Airflow sensor active filter reset?) 
            ; under a bunch of conditions 
            ;
            ; Not completly checked...
            ; TPS increased to between 26% and 50%
            ; or tps<26% and timer not expired
            ; or 4%<=tps<19% and timer expired
            ; or no TPS increase to 26% and 50%                  
            ;        and tps>=26%                                    
            ;           or 19%<=tps<26% and timer expired           
            ;           or tps<4% and timer expired                 
            ;    and idlSwOn and [ rpm<1000 or ( rpm>1000 and airVol<$40) ]
            ; .....
            ;---------------------------------------------------------------------
L1947       andm    port2, #$fb             ; reset port output??????                                                                                                                                        
            bra     L1949                   ;             
                                                                                                                                                
            ;---------------------------------------------------------------------
            ; Set port2.2 (Airflow sensor active filter reset?) 
            ; under a bunch of conditions...
            ;---------------------------------------------------------------------
L1948       orm     port2, #$04             ; Set port output???? 

            ;--------------------------
            ; Update oldTps1 at 200Hz
            ;--------------------------
L1949       ldaa    tpsRaw                  ;                                                                                                                                               
            staa    oldTps1                 ;                                                                                                                                                  

            ;----------------------------------------------
            ; Update oldTps2 and tpsDiffMax1 at 100Hz 
            ;----------------------------------------------
L1950       brset   rtiCnt, #$07, L1953     ; Branch if any of those bits set -> branch 7 out of 8 times
            ldaa    tpsRaw                  ; Code executed at ~800Hz/8=100Hz, a=tpsRaw                           
            tab                             ; b=tpsRaw                             
            suba    oldTps2                 ; a = tpsRaw-oldTps2                             
            bcc     L1951                   ; branch if result positive (tpsRaw>=oldTps2)                             
            clra                            ; Use min of 0                            
L1951       cmpa    tpsDiffMax1             ;                              
            bls     L1952                   ; branch if  (tpsRaw-oldTps2)<=tpsDiffMax1                             
            staa    tpsDiffMax1             ; tpsDiffMax1 = max(tpsDiffMax1, (tpsRaw-oldTps2))                               
L1952       stab    oldTps2                 ; oldTps2 = tpsRaw                             

            ;------------------------------------------------------
            ; Update section at 200Hz (800Hz/4) if time has come
            ;------------------------------------------------------
L1953       brset   rtiCnt, #$03, L1955     ; Branch if any of those bits set -> branch 3 out of 4 times                                

            ;-------------------------------
            ; Code executed at 200Hz
            ;-------------------------------
            ;------------------------------------------------
            ; Update T200s_sInj timer and reset sInjEnr 
            ; to 0 if timer is expired
            ;
            ; Basically brings down enrichement to 0 a 
            ; little while after it is not needed anymore
            ;------------------------------------------------
            ldaa    T200s_sInj              ; 
            beq     L1954                   ; Branch if T200s_sInj already at 0                             
            dec     T200s_sInj              ; decrement T200s_sInj                             
            bne     L1955                   ; Bail if T200s_sInj not 0 yet                             
L1954       clr     sInjEnr                 ;
                                              
            ;-----------------------------------------------------
            ; Update section at 100Hz (800Hz/8) if time has come
            ;-----------------------------------------------------
L1955       brset   rtiCnt, #$07, L1962     ; Branch if any of those bits set -> branch 7 out of 8 times                                

            ;-------------------------------
            ; Code executed at 100Hz
            ;-------------------------------
            ;------------------------------------------------------------------
            ; Section to increase simultaneous fuel injection time (sInjPw)
            ; when the gas pedal is being pressed, simultaneous injection
            ; during acceleration... 
            ;------------------------------------------------------------------
            ldaa    tpsRaw                  ; a = tpsRaw
            suba    oldTps3                 ; a = tpsRaw - oldTps3                              
            bcc     L1956                   ; Branch if result positive                              
            clra                            ; Use min of 0                             
L1956       staa    tpsDiff100              ; tpsDiff100 = max(tpsRaw - oldTps3, 0)                              
            cmpa    #$03                                                 
            bcs     L1961                   ; Bail if (tpsRaw - oldTps3) < 3                              
            ldab    oldTps3                 ;                              
            cmpb    sInjTpsMax              ;                              
            bcc     L1961                   ; Bail if oldTps3 >= sInjTpsMax                             
            brset   state3, #$35, L1961     ; Bail if "rotatingStopInj but not runningFast" or notRotating or rev limiter active or startingToCrank                                  
            brset   port3, #$80, L1961      ; Bail if idle switch on
            
            ;---------------------------------------------------------------------
            ; At this point, idle switch is off, engine is "running normally?",
            ; (tpsRaw - oldTps3) >=3 and oldTps3 < sInjTpsMax
            ;
            ; Basically means the gas pedal is moving forward, acceleration...
            ;
            ; Increase simultaneous fuel injection time if not already at max???? 
            ; Kind of acceleration enrichement when still using simultaneous 
            ; injection????
            ;---------------------------------------------------------------------
            ldaa    sInjEnr                 ; a = sInjEnr                              
            cmpa    sInjEnrMax              ;                               
            bcc     L1961                   ; Bail if sInjEnr >= sInjEnrMax (maximum enrichment reached)                             
            ldaa    #$28                    ;                             
            staa    T200s_sInj              ; Init timer T200s_sInj to $28 (0.2s)                             
            ldab    tpsDiff100              ; b = tpsDiff100                              
            lsrb                            ;                             
            lsrb                            ; b = tpsDiff100/4                            
            cmpb    #$08                    ;                             
            bcs     L1957                   ; Branch if tpsDiff100/4 < 8                              
            ldab    #$08                    ; Use max of 8                            
L1957       ldx     #t_sInjEnr              ; x = t_sInjEnr                               
            abx                             ; s = t_sInjEnr + tpsDiff100/4                           
            ldaa    $00,x                   ; a = t_sInjEnr(tpsDiff100)                             
            ldab    sInjEnrInc              ; b = sInjEnrInc                             
            mul                             ; d = sInjEnrInc * t_sInjEnr(tpsDiff100)                            
            asld                            ; d = 2 * sInjEnrInc * t_sInjEnr(tpsDiff100)                           
            bcs     L1958                   ; Branch to use max if overflow                             
            cmpa    #$15                    ;                             
            bcs     L1959                   ; Branch if 2 * sInjEnrInc * t_sInjEnr(tpsDiff100) < 15*256                             
L1958       ldaa    #$15                    ; 
            clrb                            ; Use Max of d=$1500 (5.3ms)
L1959       psha                            ; st0 = 2/256 * sInjEnrInc * t_sInjEnr(tpsDiff100)
            addd    sInjPw                  ; d = 2 * sInjEnrInc * t_sInjEnr(tpsDiff100) + sInjPw                                
            std     sInjPw                  ; sInjPw = old sInjPw + 2 * sInjEnrInc * t_sInjEnr(tpsDiff100)
            pulb                            ; b =  1/128 * sInjEnrInc * t_sInjEnr(tpsDiff100)
            addb    sInjEnr                 ;                               
            stab    sInjEnr                 ; sInjEnr = sInjEnr + 1/128 * sInjEnrInc * t_sInjEnr(tpsDiff100)
            
            ;----------------------------                                               
            ; Update oldTps3 at 100Hz)
            ;----------------------------                                               
L1961       ldaa    tpsRaw                                                 
            staa    oldTps3                                                 
            sei                                                          

            ;-------------------------------------------------------------                                               
            ; Schedule simultaneous injection injector activation and 
            ; deactivation at 100Hz, i.e. every 10ms, this is what the 
            ; tech manual says...
            ;-------------------------------------------------------------                                               
            jsr     simInject                                                 

            ;----------------------------------
            ; Re-enable interrupts and return
            ;----------------------------------
L1962       sei                                                          
            orm     t1_csr, #$18            ; Re-enable interrupt for                                                                                                      
            orm     t2_csr, #$18            ; Re-enable interrupt for                                                                                                    
            orm     rti_ctl, #$40           ; Re-enable interrupt for                                                                                                     
            brclr   obdFlags, #$02, L1963   ; Branch if serial output on port 2 was previously init to 1 (means serial rx is also init)                               
            orm     sci_scr, #$10           ; re-enable serial port "rx interrupt"
L1963       rti                                                          



;******************************************************************
;
; Output compare interrupt 3
;
; Triggered when the output compare interrupt for 
; coil energization or ignition is triggered.
;
;
;******************************************************************
outCompInt3 bsr     coilFunc                                                 
            rti                                                          



;******************************************************************
;
;
; Called by code and interrupt subroutine when an output 
; compare interrupt for coil energization or ignition is
; triggered or pending.
;
;
;******************************************************************
            ;-------------------------------------
            ; Flush both output compare registers 
            ; (write fartest possible time)
            ;-------------------------------------
coilFunc    ldx     t3_clock1               ; x = t3_clock1                                                                      
            dex                             ;                                                              
            stx     t3_outCmpWr             ; re-init count of first register
            ldaa    t3_csr1                 ;                                                                     
            stx     t3_outCmpWr             ; re-init count of second register                                     

            ;-------------------------------------------
            ; Branch to the right section depending on
            ; the current state of affairs
            ;-------------------------------------------
            brset   enerFlags, #$02, L1968       ; Branch if coil energization was scheduled and coil is therefore now energized?
            brclr   enerFlags, #$01, L1971       ; Bail if enerFlags = 0, nothing needs doing.

            ;----------------------------------------------------------------------
            ; At this point enerFlags=1, the flag indicates coil was energized
            ; and the current interrupt was for coil ignition, check if we should
            ; schedule schedule coil energization for the next cylinder
            ;----------------------------------------------------------------------
            brset   ignFallFlags, #$01, L1971    ; Bail if we decided ignition would be scheduled from the cas falling edge, In that case, energization is unlikely to be done before the cas rising edge...
            brclr   tdcCasCount, #$fe, L1967     ; Branch if tdcCasCount = 0 or 1, we are starting to crank??                                     

            ;---------------------------------------------------------------------------
            ; At this point enerFlags=1 and ignFallFlags = 0 and tdcCasCount >= 2 
            ; 
            ; Schedule interrupt to energize the coil of the next cylinder 
            ; using energization time and TDC of the next cylinder.
            ;
            ; This might be done in case the energization time falls before the cas
            ; rising edge of the next cylinder (at high rpm). This is the only 
            ; place we can schedule such an event. If on the cas rising edge the
            ; energization already occured and the coil is energized, the code will not 
            ; schedule energization again...If it did not occure, the output compare 
            ; register will be flushed and energization will be scheduled again?
            ;
            ; Note that enerFlags is set to 0 instead of 1. Probably because the coil
            ; being energized is on the next cylinder, not the current one. The 
            ; energization we are doing here is more of a precautionary measure????
            ;
            ; Note that the second output compare register was already flushed at 
            ; the beginning of subroutine. 
            ;---------------------------------------------------------------------------
            ldd     t3_clock1                ; d = t3_clock1                                  
            addd    #$0009                   ; d = t3_clock1 + $09                             
            cmpd1   enerAbsTimeNext0         ;                             
            bpl     L1966                    ; Branch to use t3_clock1 + $09 is enerAbsTimeNext0 is "in the past"
            ldd     enerAbsTimeNext0         ; enerAbsTimeNext0 is valid, use it                          
L1966       std     t3_outCmpWr              ; Schedule interrupt on first output compare register                                  
            ldaa    tdcMask1                 ; a = next tdc mask, not the current one..., $02 or $04
            asla                             ; a = $04 or $08                           
            coma                             ; a = ~($04 or $08)                           
            anda    t3_csr0                  ; reset next tdc coil bit, energize that coil at the scheduled time                            
            staa    t3_csr0                  ; update t3_csr0                            

            ;--------------------
            ; Set enerFlags = 0
            ;--------------------
L1967       clra                             ;                            
            staa    enerFlags                ;                             
            rts                              ;                            

            ;------------------------------------------------------
            ; At this point enerFlags=2, coil energization was 
            ; scheduled and coil is therefore now energized...
            ;
            ; Schedule interrupt  on first output compare register
            ; to provoke ignition at the specified time
            ; Second output compare register was already 
            ; flushed at the beginning of subroutine
            ;------------------------------------------------------
L1968       brset   ignFallFlags, #$01, L1970 ; Branch if flag indicates ignition is to be scheduled on the cas falling edge, it will be done at that time...                              
            ldd     t3_clock1                 ; d = t3_clock1                                   
            addd    #$0008                    ; d = t3_clock1 + $08                              
            cmpd1   ignTime0                  ;                               
            bpl     L1969                     ; Branch to use t3_clock1 + $08 if ignTime0 is "in the past"                            
            ldd     ignTime0                  ; ignTime0 is valid, use it                           
L1969       std     t3_outCmpWr               ; Schedule interrupt on first output compare register                                  
            orm     t3_csr0, #$0c             ; Set both coil bits, i.e. provoke ignition on the energized coil at the scheduled time?                              

            ;----------------------------------------------------
            ; Set enerFlags = 1 indicating coil is energized?
            ;----------------------------------------------------
L1970       ldaa    #$01                    ;                             
            staa    enerFlags               ;                              
L1971       rts                             ;                             



;******************************************************************
;
;
; Interrupt subroutine when a failure occurs (clock monitor??)
;
;
;******************************************************************
            ;------------------------------------
            ; Clear flag ?????
            ;------------------------------------
failureInt  andm    ramControl, #$bf             ; Reset 01000000 since we are here, disable ram??? or other function????

            ;-----------------------------------------
            ; Disable all outputs, ie.e re-init all 
            ; data direction registers to all inputs 
            ;-----------------------------------------
            clra                            ;                             
            clrb                            ;                             
            std     p1_ddr                  ; Initialize data direction registers for ports 1,2,3,4,5 to all input
            std     p3_ddr                  ;                               
            staa    p5_ddr                  ; 

            ;---------------------------------------------------------------
            ; Wait for an interrupt, I assume only system reset  
            ; can be called since other interrupts have lower priority, 
            ; might be triggered by above action on ramControl???
            ;---------------------------------------------------------------
            wai                             ; Wait for an interrupt to jump to codeStart?

            ;-----------------------------------------
            ; I assume we never get here so that 
            ; code continuation is from codeStart...
            ;-----------------------------------------

                                                    
                                                    
                                                     
;******************************************************************
;
; Code snipet from the first subroutine (jumps here and then 
; jumps back to first subroutine)
;
; This code might have been put here in case the cop function
; above (failureInt) ever skips the "wai" opcode above?? That 
; way we at least are executing some real code instead of 
; trying to execute the table content located further. Cop
; function should kick-in in a short while if everything
; is not back to normal...
;
;******************************************************************
            ;----------------------------------------------------
            ; We are in closed loop mode, limit the range
            ; of o2Fbk to $4d-$d6 or $2a-$d6 depending on ect 
            ;----------------------------------------------------
L1973       ldaa    o2Fbk                   ; a = o2Fbk                              
            ldab    ectFiltered             ; b = ectFiltered                                    
            cmpb    #$1c                    ; 86degC                              
            bcs     L1975                   ; Branch if temperature(ectFiltered) > 86degC                              

            ;-------------------------------------------------------
            ; temperature(ectFiltered) <= 86degC 
            ; Check for o2Fbk min and max of $4d and $d6
            ;-------------------------------------------------------
            cmpa    #$4d                    ;                             
            bcc     L1974                   ; Branch if o2Fbk >= $4d
            ldaa    #$4d                    ; Use min of $4d
            bra     L1976                   ; Branch to store new o2Fbk
L1974       cmpa    #$d6                    ;                             
            bcs     L1977                   ; Branch if o2Fbk < $d6                               
            ldaa    #$d6                    ; Use max of $d6                            
            bra     L1976                   ; Branch to store new o2Fbk                             

            ;--------------------------------------
            ; temperature(ectFiltered) > 86degC
            ;--------------------------------------
L1975       cmpa    #$2a                    ;                             
            jmp     L1140                   ;                              

L1976       jmp     L1142                   ; Jump to store new o2Fbk                              
L1977       jmp     L1143                   ;                             


;******************************************************************
;
;
; E932 "patch" for rpm calculation, not sure why this is here
;
;******************************************************************
#ifdef E932
L1978       ldab    rpm31                   ;                              
            ldx     #$8840                  ;                               
            jsr     clipOffset              ; b = max(min(rpm31,$88)-$40,0)-> returns b = $00 to $48  (2250rpm to 4250rpm)                                           
            aslb                            ;                             
            tba                             ;                             
            ldx     #t_closedLp2            ;                                     
            jmp     L1120                   ;                              
#endif


;******************************************************************
;
; Empty memory block
;
;******************************************************************
#ifdef E931
            .byte   $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff 
            .byte   $ff, $ff, $ff

#else
            .byte   $ff, $ff, $ff, $ff, $ff   
#endif



;******************************************************************
;
; Resistor strapping flags
;
; Stored in config1:config2 based on port4 lowest 2 bits (resistor values)
;
;
;******************************************************************
t_strap1    .word   $8200                ; Fwd  Federal   
            .word   $8401                ; Fwd  California
            .word   $8282                ; Awd  Federal    
            .word   $8483                ; Awd  California 



;******************************************************************
;
; Indicates which table to use as a function of config resistors
;
;
;
;******************************************************************
t_strap2    .word   L1999                   ; Fwd  Federal    
            .word   L2000                   ; Fwd  California 
            .word   L2001                   ; Awd  Federal    
            .word   L2002                   ; Awd  California 


;******************************************************************
;
; Resistor strapping device id returned on diagnostic port
;
;******************************************************************
t_strap3    .word   $e022                   ; Fwd  Federal    
            .word   $e023                   ; Fwd  California 
            .word   $e022                   ; Awd  Federal    
            .word   $e023                   ; Awd  California 



;******************************************************************
;
; Table values are compared to mafRaw16/64 = mafRaw -> (xx/6.25)Hz
;
; These are the 2 thresholds determining which trim range to use,
; low, mid, high. The first threshold delimiting "low" from "mid" 
; corresponds to the first two value. It is 106.5Hz with an hysteresis
; of +/-6Hz. The second threshold  delimiting mid from high correspond
; to the last two values. It is 175Hz with an hysteresis of +/-6.25Hz
;
; Values are 
;
;   $12 = 112.50 Hz 
;   $10 = 100.50 Hz 
;
;   $1d = 181.25 Hz 
;   $1b = 168.75 Hz 
;
;******************************************************************
t_ftrimRg   .byte   $12, $10, $1d, $1b    



;******************************************************************
;
; Table of rpm31 values , $23=1094rpm, $20=1000rpm, $1d=906rpm 
;
; Longer for AT
;
;******************************************************************
L1983      .byte   $23, $20
#ifdef E932
           .byte   $20, $1d    
#endif



;******************************************************************
;
; Table contains RPM/31.25, interpolated by ECT. Eventually
; used as a threshold to determine if the engine is ???.
; used in state1 flags update
;
; Value is increased as a function of loads (see t_rpmEctOff)
;
;
; (1188, 1188, 1594, ....., 3000) 
;
; IX = FB40 from L1097
; ECT
;
;******************************************************************
t_rpmEct    .byte   $26, $26, $33, $3c, $46, $50, $56, $60     



;******************************************************************
;
; Table contains RPM/31.25 offsets that will be added to 
; initial value of t_rpmEct, basically increasing RPM as a function 
; of loads
;
;       $00 = +0rpm, 
;       $08 = +250rpm, 
;       $10 = +500rpm
;       $1d = +906.25rpm
;       $0d = +406.25RPM
;
;    3 bit index into table, b2 b1 b0 where:
;
;               b0 is set if ???
;               b1 is set if tranmission is engaged
;               b2 is set if A/C switch is ON
;
; IX = FB48 from L1102
;
;******************************************************************
t_rpmEctOff .byte   $08, $00, 
            .byte   $10, $00,
            .byte   $1d, $0d, 
            .byte   $10, $00     



;******************************************************************
;
; Interpolated from modified tps and rpm
; Seems to be some kind of default air count used when we are
; not receiving airflow sensor interrupts
;
;******************************************************************
L1986
#ifdef E931
            .byte   $62, $3d, $20, $16, $12
            .byte   $7a, $7a, $78, $6c, $5c
            .byte   $7d, $7d, $9e, $c2, $c0
            .byte   $7d, $7d, $a0, $cd, $cc
            .byte   $7d, $7d, $a8, $ce, $d8
            .byte   $8a, $8a, $bb, $d0, $df
#else
            .byte   $4d, $2b, $03, $16, $12     
            .byte   $78, $84, $84, $60, $4a     
            .byte   $7a, $88, $d0, $bd, $a2     
            .byte   $7a, $88, $d2, $e9, $d0     
            .byte   $7a, $88, $de, $ee, $de     
            .byte   $7a, $8a, $da, $ec, $e4     
#endif



;******************************************************************
;
; Mas compensation table as a function of airflow sensor frequency
;
;
; Index into t_masComp table are for the following frequencies:
;
;      85   85   A8   B6   BE   C3   C8   CC   D0   D4   D7   DA   DC   E3   E6   E8   EB   EA   EA   E8   E7
; Hz    0   25   50   75   100  125  150  175  200  225  250  275  300  400  500  600  800  1000 1200 1400 1600
;
;******************************************************************
t_masComp
#ifdef custMas
            .byte   $85, $85, $A8, $B6, $BE, $C3, $C8, $CC, $D0, $D4, $D7, $DA, $DC, $E3, $E6, $E8, $EB, $EA, $EA, $E8, $E7
#else
#ifdef E931
            .byte   $5b, $5b, $59, $59, $60, $65, $6c, $6e, $6e, $6f, $73, $76, $7a, $81, $82, $84, $87, $85, $7f, $7a, $7f
#else
            .byte   $5d, $5d, $5c, $5a, $61, $68, $6c, $6f, $70, $74, $76, $77, $7a, $7f, $84, $85, $88, $86, $81, $7f, $7e 
#endif
#endif



;******************************************************************
;
; This table is an airflow sensor compensation table (for temperature 
; drift, flow characteristic change, etc?) as a function of 
; air temperature, barometric pressure and airflow frequency.
; Notice that frequency range is short which would mean airflow
; sensor only need compensation under low flow conditions...
;
; Column index are airflow sensor frequency:
;
;   0Hz 25Hz 50Hz 75Hz 100Hz 125Hz 150Hz 175Hz 200Hz
;
; Row index are max(min(L1992(iat)*baroFactor,$52)-$22,0)/16,
; at 1 bar that would correspond to (from top to bottom):
;
;   85degC, 84degC, 26degC, -31degC ?? 
;
; 2G mas table:  $87, $87, $87, $85, $85, $85, $85, $85, $80
;                $80, $80, $80, $80, $80, $80, $80, $80, $80 
;                $7d, $7d, $78, $7a, $7b, $7c, $7c, $7c, $80 
;                $7b, $7b, $75, $78, $7a, $7a, $7a, $7a, $80 
; 
;
;******************************************************************
t_masLin    .byte   $7d, $7d, $7f, $81, $84, $81, $81, $83, $80     
            .byte   $80, $80, $80, $80, $80, $80, $80, $80, $80     
            .byte   $83, $83, $83, $82, $80, $7d, $7f, $7f, $80     
            .byte   $85, $85, $85, $83, $80, $7d, $7c, $7f, $80     


;******************************************************************
;
; Interpolated using rpm (max=3000rpm)
;
; Could be maximum air count as a function of RPM, used in 
; conjucntion with L1990 and L1991
;
;******************************************************************
t_airCntMax
#ifdef E931
            .byte   $5a, $5a, $5b, $5b, $61, $63, $8f, $a0, $ff, $ff, $ff, $ff, $ff
#else
            .byte   $5f, $5f, $5f, $5f, $64, $6c, $73, $ff, $ff, $ff, $ff, $ff, $ff  
#endif



;******************************************************************
;
; Interpolated from ectCond
;
; ECT based correction factor for t_airCntMax
;
;******************************************************************
L1990       .byte   $80, $80, $80, $84, $88, $8b, $8f, $93      



;******************************************************************
;
; Interpolated from iatCond
;
; IAT based correction factor for t_airCntMax
;
;******************************************************************
L1991       .byte   $8c, $86, $83, $80, $7d, $79, $73      



;******************************************************************
;
; Interpolated from iatCond. Value from table is then compensated for 
; barometric pressure and then used to interpolate t_masLin
;
; in degC
;
;  85  56  38  23  9  -7  -31 ??
;
;******************************************************************
L1992       .byte   $45, $3b, $36, $31, $2d, $29, $22      



;******************************************************************
;
; Close loop table 1, interpolated from rpm
;
; The values of this table are airVolTB thresholds. Closed loop
; only happens when airVolTB < theshold (with hysteresis of $06)
;
; rpm scale  500 1000 1500 2000 2500 3000 3500 4000 4500 5000
;
;******************************************************************
t_closedLp1 .byte   $9d, $9d, $9d, $9d, $9d, $80, $68, $55, $00, $00      



;******************************************************************
;
; Close loop table 2, interpolated from rpm
;
; The values of this table are airVolTB thresholds. Once we are 
; in closed loop, we will remain in closed loop as long as airVolTB
; does not exceed the threshold of this table  (with hysteresis of 
; 6) for more than 12sec or 20sec.
;
; rpm scale  500 1000 1500 2000 2500 3000 3500 4000 4500 5000
;
;******************************************************************
t_closedLp2
#ifdef E931
            .byte   $9d, $9d, $9d, $a6, $ae, $ae, $9d, $73, $00, $00
#else
            .byte   $c3, $cd, $da, $eb, $cd, $aa, $68, $5f, $55, $00      
#endif



;******************************************************************
;
; Closed loop table 3, interpolated from rpm
;
; Values are tspRaw threshold. Open loop only happens 
; when tpsRaw > threshold  (with hysteresis of $0d to go
; back to closed loop)
;
; rpm scale  500 1000 1500 2000 2500 3000 3500 4000 4500 5000
;
;******************************************************************
t_closedLp3
#ifdef E931
            .byte   $5c, $66, $73, $8d, $8d, $85, $71, $5c, $00, $00
#else
            .byte   $5c, $5c, $73, $8d, $94, $8a, $66, $33, $00, $00      
#endif



;******************************************************************
;
; Closed loop fuel adjustment values,
;
; First value is used in low trim range under low speed/rpm, 
; second value in other cases
;
; Values are used in closed loop mode to adjust fuel amount:
;
;       o2FuelAdj = o2Fbk +/-  t_closedLpV1(xx) or t_closedLpV2(xx) or $02
;
; where +/- depends on o2Raw (lean or rich). 
; Basically this controls how fast we change the mixture based on o2Fbk
;
;******************************************************************
#ifdef E932
t_closedLpV2       .byte   $03, $07     
#endif



;******************************************************************
;
; Closed loop fuel adjustment values,
;
; First value is used in low trim range under low speed/rpm, 
; second value in other cases
;
; Values are used in closed loop mode to adjust fuel amount:
;
;       o2FuelAdj = o2Fbk +/-  t_closedLpV1(xx) or t_closedLpV2(xx) or $02
;
; where +/- depends on o2Raw (lean or rich). 
; Basically this controls how fast we change the mixture based on o2Fbk
;
;******************************************************************
t_closedLpV1       .byte   $03, $07



;******************************************************************
;
; Default o2Fbk decrease and increase values (in that order)
; when T40_o2Fbk is expired
;
;
;******************************************************************
t_o2Fbk1    .byte   $20, $15     



;******************************************************************
;
; Tables of o2Fbk decrease/increase values. One table for 
; each possible resistor strapping combinations
;
; Table format:
;          First sub-table of six values: o2Fbk decrease values
;          Last  sub-table of six values: 02Fbk increase values
;      
; Within each sub-table of six value we have
;          First  pair: rpm < ~1500rpm
;          Second pair: ~1500rpm < rpm < 2100rpm
;          Third  pair: rpm > 2100rpm
;
; Within each pair we have
;          First  value: airVolTB < ~40
;          Second value: airVolTB > ~40
;
;******************************************************************
#ifdef E931
L1999       .byte   $32, $42, $36, $47, $35, $43, $2e, $42, $36, $49, $37, $51     ; Fwd  Federal    
L2000       .byte   $32, $42, $36, $41, $31, $3d, $2e, $42, $36, $4f, $3b, $57     ; Fwd  California 
L2001       .byte   $32, $42, $36, $45, $34, $43, $2e, $42, $36, $4b, $38, $51     ; Awd  Federal    
L2002       .byte   $32, $42, $36, $41, $31, $3b, $2e, $42, $36, $4f, $3b, $59     ; Awd  California 
#else
L1999       .byte   $32, $46, $40, $50, $42, $52, $2e, $46, $40, $50, $42, $62     ; Fwd  Federal    
L2000       .byte   $32, $46, $40, $49, $3c, $4b, $2e, $46, $40, $57, $48, $69     ; Fwd  California 
L2001       .byte   $32, $46, $40, $4f, $41, $52, $2e, $46, $40, $51, $43, $62     ; Awd  Federal    
L2002       .byte   $32, $46, $40, $49, $3c, $48, $2e, $46, $40, $57, $48, $6c     ; Awd  California 
#endif


;******************************************************************
;
; Table of relative air density as a function of temperature
; Factor of 1.0 correspond to around 25.6degC
; Interpolated from iatCond
;
; Fits the gas law quite well, taking the two extreme 
; points (85degC and -31degC) and using Kelvins, we have
;
;             T1/T2 = density2/density1
;
; In theory
;             (273+85)/(273-31) = 1.479
;
; The table gives us
;
;              density2/density1 = 1.23/0.828 = 1.486 
;
; This is a 0.5% difference.
;
;
;        degC    85     56     38    23     9    -7    -31 
; table value   $6a    $73    $7a    $81   $87   $8f   $9e
;     density  0.828  0.898  0.953  1.01  1.05   1.12  1.23 
;
;
;******************************************************************
t_airDens   .byte   $6a, $73, $7a, $81, $87, $8f, $9e      


;******************************************************************
;
; Fuel enrichment factor as a function of airVolCond
; The value of this table reduces the enrichement of t_ectEnr 
; down to 0 as airflow is increased
;
;******************************************************************
t_airEnr    .byte   $80, $80, $80, $80, $76, $4f, $38, $38, $2d, $2a, $20, $20     



;******************************************************************
;
; Fuel enrichment factor as a function of ect (from 0% to 47% 
; enrichment in cold temp). This value is reduced by a factor taken 
; from t_airEnr when airflow is increased, see code
;
;******************************************************************
t_ectEnr
#ifdef E931
            .byte   $80, $80, $87, $89, $8f, $9d, $ab, $bc
#else
            .byte   $80, $80, $87, $89, $8f, $9a, $a4, $b5     
#endif



;******************************************************************
;
; Seem to contain enrichment values as a function of ECT
; (run richer during warm-up/start-up)
; $09 when hot, $80 when cold..., seems a bit high??????
;
;  fuel enrichment applied = ($80+2*xx)/$80, enrich=$80=100%=no enrichment
;
;  value xx  $09    $0d   $10    $1a    $27    $33    $4d    $80 
;  enrich    1.14   1.20  1.26   1.40   1.60   1.80   2.2    3.00
;
;******************************************************************
t_enrWarmup .byte   $09, $0d, $10, $1a, $27, $33, $4d, $80   


;******************************************************************
;
; Fuel map, value of $80 represent an enrichment factor of 1.0 
;
;  rpm  500 1000 1500 2000 2500 3000 3500 4000 4500 5000 5500 6000 6500 7000
;       
;       
;******************************************************************
t_fuelMap      
#ifdef custFuelMap
            .byte   $84, $82, $81, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80
            .byte   $87, $85, $84, $82, $82, $82, $82, $84, $85, $85, $85, $85, $85, $85
            .byte   $90, $8e, $8c, $8b, $8a, $8b, $8d, $8f, $8f, $90, $91, $91, $91, $91
            .byte   $94, $94, $94, $96, $98, $9a, $9c, $9e, $a0, $a2, $a4, $a6, $a8, $aa
            .byte   $a5, $a6, $a9, $ae, $b2, $b6, $b8, $b8, $ba, $ba, $ba, $ba, $bc, $bc
            .byte   $b0, $b6, $b9, $bc, $c0, $c2, $c3, $c3, $c4, $c5, $c6, $c6, $c6, $c6
            .byte   $b2, $b8, $bb, $be, $c2, $c4, $c5, $c5, $c6, $c7, $c8, $c8, $c8, $c8
            .byte   $b4, $ba, $bd, $c0, $c4, $c6, $c7, $c7, $c8, $c9, $ca, $ca, $ca, $ca
            .byte   $b6, $bc, $bf, $c2, $c6, $c8, $c9, $c9, $ca, $cb, $cc, $cc, $cc, $cc
            .byte   $b8, $be, $c1, $c4, $c8, $ca, $cb, $cb, $cc, $cd, $ce, $ce, $ce, $ce
            .byte   $b9, $bf, $c2, $c5, $c9, $cb, $cc, $cc, $cd, $ce, $cf, $cf, $cf, $cf
            .byte   $ba, $c0, $c3, $c6, $ca, $cc, $cd, $cd, $ce, $cf, $d0, $d0, $d0, $d0
#else
#ifdef E931
            .byte   $8d, $85, $80, $7c, $7f, $7f, $80, $82, $85, $85, $85, $98, $98, $a0
            .byte   $8d, $85, $80, $7c, $7f, $7f, $80, $83, $85, $85, $85, $98, $98, $a0
            .byte   $8d, $85, $80, $80, $80, $80, $80, $80, $80, $80, $80, $98, $98, $a0
            .byte   $8d, $86, $80, $80, $80, $80, $80, $83, $84, $8a, $96, $98, $9f, $a7
            .byte   $91, $86, $80, $80, $80, $80, $80, $85, $8f, $96, $98, $a8, $a8, $ae
            .byte   $92, $9c, $98, $80, $80, $80, $86, $90, $98, $a0, $a6, $af, $af, $b6
            .byte   $94, $9e, $98, $80, $80, $87, $91, $98, $a5, $a8, $b3, $b6, $b6, $be
            .byte   $94, $9e, $98, $98, $95, $93, $98, $a0, $ac, $b0, $b8, $bb, $be, $c5
            .byte   $94, $9e, $98, $98, $96, $a0, $a8, $a8, $b3, $b8, $bd, $c0, $c6, $ca
            .byte   $94, $9e, $98, $98, $a7, $b4, $ae, $b3, $ba, $bf, $c3, $c4, $ca, $ca
            .byte   $94, $9e, $98, $98, $a7, $b6, $b8, $b9, $c4, $c8, $ca, $c8, $ca, $ca
            .byte   $94, $9e, $98, $98, $a7, $b6, $b8, $b9, $ca, $ca, $ca, $c8, $ca, $ca

#else
            .byte   $8d, $85, $80, $7e, $7c, $7c, $7c, $7c, $85, $89, $9a, $a0, $a0, $a3       
            .byte   $8d, $85, $80, $7e, $7c, $7c, $7c, $7c, $85, $89, $9a, $a0, $a0, $a3       
            .byte   $8d, $85, $80, $7e, $7c, $7c, $7c, $7c, $85, $89, $9a, $a0, $a0, $a3       
            .byte   $8d, $85, $80, $7e, $7c, $7c, $7c, $8a, $90, $96, $a0, $a3, $a6, $a9       
            .byte   $91, $85, $80, $7e, $7c, $7c, $86, $90, $9a, $a0, $a4, $a9, $aa, $ad       
            .byte   $97, $97, $80, $7e, $7c, $94, $91, $9c, $a0, $a3, $aa, $ac, $b2, $b5       
            .byte   $97, $97, $99, $7e, $92, $94, $95, $a2, $a8, $a8, $ad, $b3, $b9, $bb       
            .byte   $97, $97, $99, $92, $92, $98, $9f, $a8, $ac, $ad, $b2, $b9, $bb, $be       
            .byte   $97, $97, $99, $92, $9c, $a2, $a7, $ac, $b3, $b4, $b7, $bc, $bc, $c0       
            .byte   $97, $97, $99, $a4, $a9, $ac, $ad, $b0, $b7, $bb, $bd, $bc, $c0, $c0       
            .byte   $97, $97, $99, $aa, $ae, $b0, $b2, $b6, $bd, $c0, $c0, $c0, $c0, $c0       
            .byte   $97, $97, $99, $aa, $ae, $b0, $b2, $b6, $bd, $c0, $c0, $c0, $c0, $c0       
#endif
#endif



;******************************************************************
;
;
; Injector deatime as a function of battery voltage 
;
; Each unit correspond to 24us ($08 = 192us)
;
;
; Volts: 4.7, 7.0, 9.4, 11.7, 14.1, 16.4, 18.8
;
;******************************************************************
t_deadtime
#ifdef custDeadTime
            ; Denso 660 .byte   $b0, $5f, $37, $2a, $22, $1e, $1a
            ; Worchester, fuel trim =  125,105, 100? .byte   $b5, $64, $3c, $2f, $27, $23, $1f
            ; Worchester, fuel trim = <81, 102, 100? .byte   $bc, $6b, $43, $36, $2e, $2a, $26
            ; Worchester, fuel trim = <81, 100, 103  .byte   $b9, $68, $40, $33, $2b, $27, $23
            .byte   $b7, $66, $3e, $31, $29, $25, $21
#else
#ifdef E931
            .byte   $a9, $58, $30, $23, $1b, $17, $13
#else
            .byte   $a8, $5a, $32, $26, $1a, $17, $11      
#endif
#endif



;******************************************************************
;
; Table used for the calculation of injPwStart
;
; non constant sample spacing:
;
;   ectCond/32          ectCond<$c0     
;   (2*ectCond-$c0)/32  ectCond>=$c0
;
;   scale in degC:
;   
;        86 80 52 35 21 8 -7 -16 -29 
;
;******************************************************************
L2008 
#ifdef E931
            .byte   $07, $07, $0d, $14, $22, $36, $60, $83, $a6 
#else
            .byte   $07, $07, $0d, $14, $22, $39, $65, $8a, $af     
#endif



;******************************************************************
;
; ect
;
;
;******************************************************************
t_accEnr2a  .byte   $17, $17, $28, $45, $60, $70, $80, $80     



;******************************************************************
;
; rpm
;
;
;******************************************************************
t_accEnr1   .byte   $ff, $b0, $a8, $80, $80, $88, $90, $a0, $b0, $c0     



;******************************************************************
;
; Table is interpolated from ect and used to initialize
; accEnrDecay. Basically the values in this table are
; the decay factor applied to accEnr on each iteration
;
;     accEnr = accEnr * (1-t_accEnrDecay(ect)/256)
;
; Slower decay under cold conditions...
;
;******************************************************************
t_accEnrDecay   .byte   $a0, $a0, $f3, $f6, $f7, $f8, $f9, $fa     



;******************************************************************
;
; Interpolated from tpsDiff100/4
;
; Used to compute fuel enrichement when doing simultaneous 
; injection under acceleration. It is basically a multipler
; of the basic enrichment time (sInjEnrInc) depending on 
; how much acceleration is requested, i.e. how fast the pedal is 
; moving
;
;******************************************************************
t_sInjEnr       .byte   $03, $04, $05, $07, $09, $0b, $0e, $11, $18     



;******************************************************************
;
; Table interpolated from ect. Used in the calculation
; of sInjEnrInc, fuel enrichment factor for sim injection 
; during acceleration
;
;******************************************************************
L2013       .byte   $00, $00, $04, $12, $18, $20, $30, $40     



;******************************************************************
;
; Values are used as a maximum threshold on TPS when calculating fuel 
; enrichement for simultaneous injection
;
; rpm scale: 500 1000 1500 2000 2500 3000 3500 4000 4500 5000
;
;******************************************************************
t_sInjTpsMax  .byte   $5b, $6c, $76, $85, $94, $b3, $cd, $cd, $cd, $cd   



;******************************************************************
;
; IX = FD2C from L1213
; 5 10 15 20 25 30 35 40 45 50 x 100 RPM
;
;******************************************************************
L2015       .byte   $30, $28, $20, $20, $20, $20, $20, $20, $20, $20   



;******************************************************************
;
; XX = FD36 from L1207
;
;******************************************************************
t_decEnr2       .byte   $50, $50, $8c, $b4, $f0, $f0, $ff, $ff    



;******************************************************************
;
; IX = FD3E from L1206
;
;******************************************************************
t_decEnr1       .byte   $1a, $20, $26, $2d, $33, $4d, $66, $80, $c0, $ff    



;******************************************************************
;
; Table of timing values under high octane conditions, values are shifted by
; 10deg in oder to allow for timing retard (0 = -10deg advance, 18 = 8 deg advance)
; It contains timing values to use when octane=255 (no knock)
;
; Timing used is interpolated from 
;
;       timingOct = alpha * t_timingHiOct(rpm, load) + (1-alpha) * t_timingLoOct(rpm, load)
;
; where alpha = octane/255, 0<= alpha <=1
;
;  rpm  500 1000 1500 2000 2500 3000 3500 4000 4500 5000 5500 6000 6500 7000 7500 8000
;
;******************************************************************
t_timingHiOct
#ifdef custTimingMap
            .byte   $14, $1a, $23, $26, $29, $2b, $2e, $30, $32, $32, $32, $32, $32, $32, $32, $32
            .byte   $14, $1a, $22, $25, $26, $27, $2a, $2b, $2c, $2c, $2c, $2c, $2c, $2c, $2d, $2d
            .byte   $13, $18, $1e, $20, $21, $24, $27, $27, $27, $27, $27, $27, $28, $2a, $2b, $2b
            .byte   $12, $16, $18, $1c, $1d, $1e, $21, $23, $24, $24, $25, $25, $26, $28, $29, $29
            .byte   $11, $12, $16, $18, $19, $1a, $1c, $1f, $21, $22, $23, $23, $26, $28, $28, $28
            .byte   $10, $11, $12, $14, $15, $16, $17, $19, $1a, $1c, $1d, $1e, $20, $22, $24, $24
            .byte   $0f, $10, $11, $12, $13, $14, $15, $16, $17, $19, $1a, $1b, $1d, $1f, $21, $21
            .byte   $0d, $0d, $0e, $0f, $10, $12, $13, $14, $15, $17, $18, $19, $1b, $1d, $1f, $1f
            .byte   $0b, $0c, $0c, $0d, $0e, $10, $11, $12, $13, $15, $16, $17, $19, $1b, $1c, $1d
            .byte   $0a, $0b, $0b, $0c, $0d, $0e, $0f, $10, $11, $13, $14, $15, $17, $19, $1a, $1b
            .byte   $09, $0a, $0a, $0b, $0b, $0c, $0d, $0e, $0f, $11, $12, $13, $15, $17, $18, $19
            .byte   $08, $09, $09, $0a, $0a, $0b, $0c, $0c, $0d, $0f, $10, $11, $13, $15, $16, $17
#else
#ifdef E931
            .byte   $12, $17, $1c, $22, $28, $2f, $30, $31, $32, $33, $36, $37, $37, $37, $37, $37 
            .byte   $12, $17, $1d, $23, $27, $2d, $2e, $30, $30, $32, $34, $37, $37, $37, $37, $37 
            .byte   $12, $18, $1f, $25, $28, $2b, $2d, $2f, $32, $32, $32, $32, $32, $32, $32, $32
            .byte   $12, $1a, $22, $26, $28, $29, $2a, $2d, $2d, $2d, $2d, $2d, $2f, $2f, $2f, $2f 
            .byte   $12, $1a, $22, $25, $25, $27, $28, $2b, $2b, $2b, $2b, $2b, $2b, $2b, $2d, $2d 
            .byte   $12, $18, $20, $22, $22, $23, $26, $28, $28, $28, $28, $28, $29, $2a, $2c, $2d 
            .byte   $12, $18, $19, $1c, $1d, $1f, $24, $25, $25, $25, $26, $26, $27, $29, $2b, $29 
            .byte   $0f, $16, $18, $1c, $19, $19, $1e, $22, $24, $24, $25, $25, $26, $28, $28, $24 
            .byte   $0c, $12, $16, $18, $19, $17, $19, $1e, $22, $22, $23, $23, $26, $28, $26, $20 
            .byte   $0a, $0f, $13, $16, $17, $17, $15, $19, $1d, $1f, $20, $21, $23, $27, $22, $1d 
            .byte   $08, $0d, $11, $14, $15, $16, $15, $19, $19, $1c, $1c, $1d, $20, $23, $1e, $1d 
            .byte   $06, $0b, $0f, $12, $13, $14, $14, $18, $19, $1c, $1c, $1d, $20, $22, $1e, $1c 
#else
            .byte   $12, $17, $1c, $22, $28, $2f, $30, $31, $32, $33, $36, $37, $37, $37, $37, $37      
            .byte   $12, $17, $1d, $23, $27, $2d, $2d, $2d, $2d, $30, $33, $37, $37, $37, $37, $37      
            .byte   $12, $18, $1e, $25, $28, $2a, $2a, $2e, $2e, $2f, $2e, $2d, $2d, $2d, $2a, $2a      
            .byte   $12, $19, $1f, $23, $24, $28, $28, $2a, $2a, $2a, $2a, $2a, $2a, $2a, $2a, $2a      
            .byte   $12, $1a, $20, $21, $22, $24, $25, $27, $27, $27, $27, $27, $28, $28, $28, $28      
            .byte   $12, $1a, $1d, $20, $21, $22, $23, $24, $25, $25, $26, $26, $27, $27, $27, $27      
            .byte   $12, $16, $18, $19, $1c, $1e, $20, $22, $24, $24, $25, $26, $26, $27, $26, $24      
            .byte   $0f, $14, $16, $16, $14, $16, $1a, $22, $24, $24, $24, $24, $25, $27, $24, $22      
            .byte   $0c, $12, $14, $16, $12, $13, $17, $1d, $21, $22, $22, $22, $24, $26, $22, $20      
            .byte   $0a, $10, $12, $14, $0f, $10, $15, $1a, $1d, $20, $20, $20, $22, $24, $20, $1e      
            .byte   $08, $0e, $10, $12, $0d, $10, $15, $19, $1c, $1f, $1f, $1f, $21, $22, $1f, $1e      
            .byte   $06, $0c, $0e, $10, $0c, $0e, $15, $19, $1c, $1e, $1e, $1f, $21, $20, $1f, $1d      
#endif
#endif



;******************************************************************
;
; Table of timing values under low octane conditions values are shifted by
; 10deg in oder to allow for timing retard (0 = -10deg advance, 18 = 8 deg advance)
; It contains timing values to use when octane=0 (lots of knock)
;
; Timing applied is interpolated from 
;
;       timingOct = alpha * t_timingHiOct(rpm, load) + (1-alpha) * t_timingLoOct(rpm, load)
;
; where alpha = octane/255, 0<= alpha <=1
;
; Note that the first three rows of t_timingLoOct have been eliminated from 
; this table (t_timingLoOct correspond to the last 9 rows of t_timingHiOct)
;
;
;******************************************************************
t_timingLoOct
#ifdef custOctaneMap
            .byte   $12, $16, $18, $1c, $1d, $1e, $21, $23, $24, $24, $25, $25, $26, $28, $29, $2a
            .byte   $11, $12, $16, $18, $19, $1a, $1c, $1f, $21, $22, $23, $24, $25, $27, $28, $29
            .byte   $10, $11, $12, $14, $15, $16, $17, $19, $1a, $1c, $1d, $1e, $20, $22, $24, $24
            .byte   $0f, $10, $11, $12, $13, $14, $15, $16, $17, $19, $1a, $1b, $1d, $1f, $21, $21
            .byte   $0b, $0d, $0e, $0f, $10, $12, $13, $14, $15, $17, $18, $19, $1b, $1d, $1f, $1f
            .byte   $0a, $0c, $0c, $0d, $0e, $10, $11, $12, $13, $15, $16, $17, $19, $1b, $1c, $1d
            .byte   $09, $0b, $0b, $0c, $0d, $0e, $0f, $10, $11, $13, $14, $15, $17, $19, $1a, $1b
            .byte   $08, $0a, $0a, $0b, $0b, $0c, $0d, $0e, $0f, $11, $12, $13, $15, $17, $18, $19
            .byte   $07, $08, $09, $0a, $0a, $0b, $0c, $0c, $0d, $0f, $10, $11, $13, $15, $16, $17
#else
#ifdef E931
            .byte   $12, $1a, $22, $26, $28, $29, $2a, $2d, $2d, $2d, $2d, $2d, $2f, $2f, $2f, $2f 
            .byte   $12, $19, $1e, $21, $22, $24, $27, $2a, $2a, $2a, $2a, $2a, $2c, $2c, $2d, $2d 
            .byte   $0c, $13, $19, $1d, $1e, $20, $24, $27, $28, $28, $28, $28, $28, $2a, $2a, $27 
            .byte   $09, $0c, $11, $14, $15, $1b, $21, $24, $25, $25, $25, $25, $25, $25, $24, $20 
            .byte   $07, $0c, $0d, $0e, $11, $13, $1b, $1f, $1f, $21, $23, $24, $24, $22, $22, $1c 
            .byte   $05, $0a, $0b, $0c, $0e, $0e, $14, $18, $1d, $1e, $1e, $1f, $21, $21, $20, $1a 
            .byte   $03, $08, $09, $0a, $0c, $0c, $0f, $16, $18, $1a, $1c, $1c, $1d, $20, $1e, $18 
            .byte   $01, $06, $07, $08, $0b, $0b, $0e, $10, $15, $17, $17, $18, $18, $1a, $18, $16 
            .byte   $00, $04, $05, $06, $0a, $0a, $0c, $0e, $12, $13, $14, $16, $16, $18, $16, $14 
#else
            .byte   $12, $19, $1f, $23, $24, $28, $28, $2a, $2a, $2a, $2a, $2a, $2a, $2a, $2a, $2a      
            .byte   $12, $1c, $21, $23, $24, $26, $28, $2a, $2a, $2a, $2a, $2a, $2a, $2a, $2a, $2a      
            .byte   $12, $14, $19, $1b, $1e, $20, $24, $27, $26, $29, $29, $29, $2a, $2a, $2a, $2a      
            .byte   $0c, $10, $12, $14, $16, $18, $1c, $26, $26, $26, $25, $24, $26, $27, $27, $24      
            .byte   $0b, $0f, $0d, $0e, $0e, $11, $16, $1b, $1d, $20, $1c, $1b, $21, $22, $22, $1c      
            .byte   $09, $0d, $0b, $0c, $0c, $0c, $10, $17, $18, $1a, $1a, $19, $1e, $20, $1e, $18      
            .byte   $07, $0b, $09, $0a, $0a, $0b, $0e, $12, $15, $17, $17, $18, $1b, $1d, $1a, $16      
            .byte   $05, $09, $07, $08, $08, $09, $0d, $0f, $12, $15, $15, $16, $19, $1a, $18, $14      
            .byte   $03, $07, $05, $06, $06, $07, $0b, $0d, $10, $13, $13, $14, $17, $18, $16, $12      
#endif
#endif


;******************************************************************
;
; Interpolated from ect, used in timing advance calculations
;
;       $81 =  1 deg advance
;       $80 =  0 deg
;       $7f = -1 deg advance
;
;******************************************************************
L2020       .byte   $80, $80, $80, $80, $80, $84, $88, $8b      



;******************************************************************
;
; Interpolated from iat, values used in 
; timing advance calculations
;
;       $81 =  1 deg advance
;       $80 =  0 deg
;       $7f = -1 deg advance
;
;******************************************************************
L2021       .byte   $7d, $7f, $80, $80, $80, $7f, $7e    



;******************************************************************
;
; Interpolated from battRaw. Values are basic coil 
; energization time, each unit correspond to 64usec?
;
;
; Voltages: 9.38v  10.56v  11.73v  12.9v  14.1v  15.2v  16.4v  17.6v  18.8v 
;
;******************************************************************
t_enerLen       .byte   $bc, $9c, $7a, $64, $56, $49, $42, $3a, $37    



;******************************************************************
;
; Interpolated from ect, This is the isc step offset added to the
; base isc step when the engine is started.
;
;
;******************************************************************
L2023       .byte   $1f, $1a, $1b, $1c, $21, $2b, $3b, $46     



;******************************************************************
;
; Interpolated from ect, values xx are loaded 
; into T40_iscStart to produce 40/xx Hz
;
;******************************************************************
L2024       .byte   $07, $07, $07, $07, $07, $08, $0a, $0c     




;******************************************************************
;
; Target idle speed as a function of ect
;
;       idle speed = xx * 7.8125
;
; default = 750, 750, 1000, 1148, 1273, 1398, 1500, 1648   
;******************************************************************
t_idleSpd   .byte   idleVal, idleVal, $80, $93, $a3, $b3, $c0, $d3    



;******************************************************************
;
; AT specific table (in drive???)
;
;       idle speed = xx * 7.8125
;
;   default = 648,  648,  797,  898,  1000, 1047, 1101, 1148
;******************************************************************
#ifdef E932
t_idleSpdDr .byte   idleDrVal, idleDrVal, $66, $73, $80, $86, $8d, $93     
#endif



;******************************************************************
;
; Target or basic ISC step value as a function of ect
; Used for instance to set iscStepTarg during basic 
; idle speed adjustment
;
;******************************************************************
t_iscStEct0
#ifdef E931
            .byte   $09, $12, $2e, $3b, $3c, $41, $4a, $54
#else
            .byte   $09, $10, $34, $3f, $46, $50, $5a, $64    
#endif



;******************************************************************
;
; Target ISC step value as a function of ect
;
; AT specific table. This table corresponds to t_iscStEct0
; but is used when AT is in drive
;
;******************************************************************
#ifdef E932
t_iscStEct1       .byte   $0c, $13, $3c, $46, $4e, $58, $64, $6e  
#endif


;******************************************************************
;
; Interpolated from conditionned TPS (conTps) (see main code)
;
; This is related to the minimum isc step to use when the idle
; switch transition from off to on and rpm8 goes too low (500rpm)
; We don't want the engine to stall...
;
;
;******************************************************************
t_iscStStall    .byte   $09, $23, $2c, $3b, $45, $4c, $53     



;******************************************************************
;
; AT specific table, equivalent of t_iscStStall when not in park/neutral 
;
;******************************************************************
#ifdef E932
L2030       .byte   $09, $23, $45, $4f, $4f, $4f, $4f     
#endif



;******************************************************************
;
; Interpolated from ect, contains ISC step values
;
;******************************************************************
L2031       .byte   $5a, $5a, $5a, $64, $6e, $78, $78, $78     



;******************************************************************
;
; Table is interpolated from (rpm4/2 - idleSpdTarg)/4. 
; Values are timer values (40Hz) used to update T40s_iscStable
; when idle switch is off (isc is considered stable when this 
; timer expires...).
;
;******************************************************************
t_iscStableIdleSw  .byte   $50, $50, $6e, $82, $96, $aa, $be, $d2, $e6, $f4, $ff   



;******************************************************************
;
; ISC pattern sequence to load to port5 bit 6 
; and 7 to move the ISC spindle 
;
;
;                       --> move spindle
;           bit 7      1 0 0 1 
;           bit 6      0 0 1 1
;
;******************************************************************
t_iscPattern  .byte   $80, $00, $40, $c0     



;******************************************************************
;
; ISC step offset as a function of barometric pressure?
; The value in this table is added to iscStepCurr to compensate 
; for barometric pressure
;
; Table interpolated with baroCond (0.45bar to 0.92bar)
; which means there is no offset ($00) when baroCond > 0.92bar
;
;******************************************************************
t_iscStBaro .byte   $1a, $12, $09, $04, $00    



;******************************************************************
;
; Interpolated from 4 * abs(idleSpdTarg - rpm8), the difference 
; between target idle speed and the current rpm
;
; Values are compared to iscStepTarg 
;
;******************************************************************
L2035       .byte   $00, $02, $06, $0a, $0d, $0e, $0e, $0f, $0f      



;******************************************************************
;
; Used in the calculation of the default air count when we are
; not receiving airflow sensor interrupts, interpolated from ect
; Seem to be some kind of tps offset...
;
;******************************************************************
L2036       .byte   $00, $00, $00, $02, $03, $04, $0a, $10     



;******************************************************************
;
; Open loop minimum fuel enrichment table ($80=100) 
; interpolated by TPS
;
;
;******************************************************************
t_tpsEnr    .byte   $78, $80, $90, $92    



;******************************************************************
;
; Interpolated from rpm, contains airVolB thresholds used in 
; timing advance calculations, used in conjuction with L2021
;
;     500 1000 1500 2000 2500 3000 3500 4000 4500 5000
;
;******************************************************************
L2038       .byte   $00, $00, $71, $71, $71, $80, $90, $a0, $a0, $a0    



;******************************************************************
;
; Table contains airCnt0 thresholds as a function of RPM
;
;    airCnt0 > $57*L2039(rpm)/16 ?
;
;    5 10 15 20 25 30 35 40 45 50 x 100 RPM
;
;******************************************************************
L2039       .byte   $6d, $6d, $85, $b4, $c8, $d0, $d6, $f0, $ff, $ff     



;******************************************************************
;
; Acceleration enrichment
;
; Interpolated from L2040(min(oldAirCnt0/256,5))
;
;******************************************************************
L2040       .byte   $0b, $0b, $0d, $10, $15, $1b      



;******************************************************************
;
; Interpolated from f(rpm4)
;
; Table contain airVol threshold values 
;
;******************************************************************
L2041       .byte   $ff, $ff, $ff, $ff, $ff, $9b, $a0, $a5, $b8, $c8, $d0, $ff   



;******************************************************************
;
; Table used for the calculation of injPwStart
; Only factored-in if injCount<5 (when the engine starts to crank??)
;
; non constant sample spacing:
;
;   ectCond/32          if ectCond<$c0     
;   (2*ectCond-$c0)/32  if ectCond>=$c0
;
;   scale in degC:
;   
;        86 80 52 35 21 8 -7 -16 -29 
;
;******************************************************************
L2042       .byte   $00, $00, $00, $00, $00, $00, $00, $20, $40      



;******************************************************************
;
;
; Boost gauge scale interpolated from airVolT/16
;
;
;******************************************************************
t_bGauge       .byte   $02, $05, $08, $0a, $0d, $0f, $11, $13, $14     



;******************************************************************
;
; EGR solenoid duty cycle 
; as a function of rpm(column) and airVol(row)
;
;******************************************************************
t_egrDutyFact 
#ifdef E931
            .byte   $00, $00, $00, $00, $00, $00, $00, $00
            .byte   $00, $00, $00, $5b, $56, $4c, $4d, $00
            .byte   $00, $00, $00, $5b, $56, $4c, $4d, $00
            .byte   $00, $00, $00, $5b, $56, $60, $5c, $00
            .byte   $00, $00, $60, $76, $6c, $5f, $5b, $00
            .byte   $80, $80, $80, $7d, $6e, $5f, $60, $00
            .byte   $80, $80, $80, $80, $76, $68, $61, $00
            .byte   $80, $80, $80, $80, $80, $60, $61, $00
            .byte   $00, $80, $80, $80, $80, $78, $6e, $00
#else
            .byte   $00, $00, $00, $00, $00, $00, $00, $00     
            .byte   $00, $00, $00, $5a, $40, $3b, $41, $00     
            .byte   $00, $00, $00, $5a, $40, $3b, $41, $00     
            .byte   $00, $00, $00, $4c, $48, $5a, $56, $00     
            .byte   $00, $00, $53, $4d, $5d, $57, $55, $00     
            .byte   $80, $80, $68, $6a, $5c, $57, $53, $00     
            .byte   $80, $80, $80, $6e, $5f, $57, $55, $00     
            .byte   $80, $80, $80, $80, $5f, $5a, $56, $00     
            .byte   $00, $80, $80, $80, $80, $80, $80, $00     
#endif




;******************************************************************
;
; EGR solenoid duty cycle as a function of ECT
;
; Value of $00 to $80 will produce 
; 0 to 100% duty cycle 
; 
;
;******************************************************************
t_egrDuty   .byte   $80, $80, $5b, $4f, $00, $00, $00, $00     



;******************************************************************
;
; Interpolated from iat, values are used as minimum egrt
; temperature for egrt sensor to be considered as working correctly
;
; if temperature(egrtRaw) < L2046(iat) then egrt is probably in error
;
;
; in degCC for E931: 83 83 53 41 31 -31 -68
;
;******************************************************************
L2046
#ifdef E931
            .byte   $9a, $9a, $ae, $b6, $bd, $e6, $ff
#else
            .byte   $9a, $9a, $a4, $ab, $bd, $e6, $ff      
#endif



;******************************************************************
;
; Interpolated from rpm, values are used as minimum airVol
; to verify if egrt sensor is working properly
;
;     500 1000 1500 2000 2500 3000 3500 4000 4500 5000
;
;******************************************************************
L2047 
#ifdef E931
            .byte   $60, $60, $58, $44, $35, $33, $30, $30, $30, $30
#else
            .byte   $60, $60, $60, $4c, $40, $38, $33, $30, $30, $30    
#endif



;******************************************************************
;
; Interpolated from rpm, values are used as maxmimum airVol
; to verify if egrt sensor is working properly
;
;     500 1000 1500 2000 2500 3000 3500 4000 4500 5000
;
;******************************************************************
L2048 
#ifdef E931
            .byte   $60, $60, $68, $88, $98, $9c, $a4, $88, $88, $88
#else
            .byte   $60, $60, $78, $98, $a8, $b0, $b0, $b0, $b0, $b0     
#endif



;******************************************************************
;
; Table interpolated from ect
;
;******************************************************************
t_accEnr2b       .byte   $1c, $1e, $30, $53, $73, $86, $9a, $9a    



;******************************************************************
;
; Table interpolated from ect. Used in the calculation
; of sInjEnrInc, fuel enrichment factor for sim injection 
; during acceleration
;
;******************************************************************
L2050       .byte   $10, $14, $18, $29, $30, $3a, $4d, $60      



;******************************************************************
;
; Table interpolated from ect. Values are timer thresholds (2Hz timer)
; used in deciding acceleration enrichment factor and simultaneous 
; injection enrichment
;
;******************************************************************
L2051       .byte   $1e, $22, $2e, $36, $3c, $42, $4a, $56       



;******************************************************************
;
; Piecewise linear rpm transformation data
;
; Using pwiseLin with this table, we get input(x)/output(y) relationship:
;
;           $00<=x<=$03 -> y = 0 
;           $04<=x<=$07 -> y = x-$03 
;           $08<=x<=$1c -> y = (x+$02)/2
;           $1d<=x      -> y = ($1c+$02)/2
;
;    First row is 
;           max, offset
;    Other rows (i=1 to n) are
;           addVal(i), nshift(i), compVal(i)  
;
;******************************************************************
L2052       .byte   $1c, $03, 
            .byte   $00, $01, $05, 
            .byte   $05, $02, $ff      



;******************************************************************
;
; Piecewise linear rpm transformation data
;
; Using pwiseLin with this table, we get input(x)/output(y) relationship:
;
;           $00<=x<=$02 -> y = 0 
;           $03<=x<=$03 -> y = (x-$02)/2 
;           $04<=x<=$10 -> y = x/4 
;           $11<=x      -> y = $10/4
;
;    First row is 
;           max, offset
;    Other rows (i=1 to n) are
;           addVal(i), nshift(i), compVal(i)  
;
;******************************************************************
L2053       .byte   $10, $02, 
            .byte   $00, $02, $02, 
            .byte   $02, $03, $ff



;******************************************************************
;
; Piecewise linear mafRaw16 (gramOfAir/sec) transformation data
; Note that this table is the same in 2G ECUs so that it doesn't need
; to be changed if 2G maf is used...
;
; The output of pwiseLin using this table is used to interpolate t_masComp
; This means that t_masComp is a table with non-constant spacing between values
; The spacing is given by the transformation in this table...
;
; Using pwiseLin with this table, we get input(x)/output(y) relationship:
;
;           $00<=x<=$0b -> y = x 
;           $0c<=x<=$17 -> y = (x+$24)/4 
;           $18<=x<=$40 -> y = (x+$60)/8 
;           $41<=x      -> y = ($40+$60)/8
;
;    First row is 
;           max, offset
;    Other rows (i=1 to n) are
;           addVal(i), nshift(i), compVal(i)  
;
;******************************************************************
L2054       .byte   $40, $00, 
            .byte   $00, $01, $0c, 
            .byte   $24, $03, $18, 
            .byte   $60, $04, $ff 
            
;******************************************************************
;
; Unused??????
;
;******************************************************************
L2055       .byte    $01, $01     



;******************************************************************
;
; Interrupt vector
;      
;      
;
;******************************************************************
#if  (codeOffset > 0)
            .fill   intVector-$, $ff
#endif
intVector   .org    $ffe0
            .word   serialRxInt   ; Serial port Rx interrupt subroutine
            .word   reset         ; ???
            .word   realTimeInt   ; Real time interrupt (801.28Hz)
            .word   reset         ; ???                     
            .word   reset         ; ???
            .word   reset         ; ???                            
            .word   outCompInt3   ; Output compare interrupt3 (coil power transistor activation/deactivation)
            .word   outCompInt2   ; Output compare interrupt2 (injector 2 or 3 activation/deactivation)                            
            .word   outCompInt1   ; Output compare interrupt1 (injector 1 or 4 activation/deactivation)                         
            .word   reset         ; ???
            .word   inCaptInt2    ; Input capture interrupt 2 (airflow sensor pulse)
            .word   inCaptInt1    ; Input capture interrupt 1 (cas rising or falling edge)
            .word   reset         ; Illegal opcode trap?
            .word   reset         ; Cop failure?
            .word   failureInt    ; Timer clock failure?
            .word   codeStart     ; System reset              
            .end




