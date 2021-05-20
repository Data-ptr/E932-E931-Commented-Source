This is the symbolic and commented source code for the DSM E931 
and E932 ECU. To assemble "standard_E932_E931_source.asm", 
download the telemark assembler TASM from http://home.comcast.net/~tasm/ 
to the same directory and execute asm.bat from the DOS prompt.
The assembler will produce two files: standard_E932_E931_source.lst
is a line by line listing of the assembly with addresses while 
standard_E932_E931_source.obj is the 32KB binary image to burn 
on EPROM. Default setting produces the E931 standard binary image


Required file, not provided (from http://home.comcast.net/~tasm/):
    TASM.EXE,  Version 3.2

Contents:
   standard_E932_E931_source.asm
      Assembly source file for the E931/E932. See notes at  
      the beginning of that file for more details. Default 
      setting produces the standard E931 EPROM image.
   asm.bat
      Batch file to assemble standard_E932_E931_source.asm
   standard_E931.bin
      Binary file read from an actual E931 EPROM. Assembly of 
      standard_E932_E931_source.asm using the "E931" setting 
      should produce an identical binary.
   standard_E932.bin
      Binary file read from an actual E932 EPROM. Assembly of 
      standard_E932_E931_source.asm using the "E932" setting 
      should produce an identical binary.
   standard_E931.lst 
      Assembly listing file for the standard E931, usefull if 
      you just want to edit an EPROM image without assembly..
   standard_E932.lst 
      Assembly listing file for the standard E932, usefull if 
      you just want to edit an EPROM image without assembly..
   tasm6111.tab
      TASM compatible opcodes for the E931/E932 ECUs. Works with the provided 
      source files. Might be incomplete if you want to use something not already
      used by the standard code...

Christian
christi999@hotmail.com