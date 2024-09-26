# Descripción de los test realizados

## Test sobre el receptor

Se realizaron test para comprobar el correcto funcionamiento del procesamiento de datos por parte del receptor. Estos se encuentran en el archivo [test RX](eth_mac_10g_tb.v).

Los objetivos generales son

| Número de Test | Descripción del Test                                                                 | Resultado Esperado                                    | Resultado obtenido      |
|----------------|--------------------------------------------------------------------------------------|------------------------------------------------------|----------------|
| 1              | Frame Ethernet (paquete sin Preambulo y SFD) de dimensión mínima de 64 bytes con 46 bytes de data todos 0s  | Datos en AXI por 46 bytes con todos 0s.               | TEST OK        |
| 2              | Frame Ethernet (paquete sin Preambulo y SFD) de dimensión mínima de 1518 bytes con 1500 bytes de data todos 0s | Datos en AXI por 1500 bytes con todos 0s.             | TEST OK        |
| 3              | Frame Ethernet (paquete sin Preambulo y SFD) de dimensión mínima de 64 bytes con data 45 bytes en 0s + 1 byte de padding | Datos en AXI por 45 bytes con todos 0s.               | TEST OK        |
| 4              | Frame Ethernet (paquete sin Preambulo y SFD) de dimensión mínima de 1519 bytes con data 1501 bytes en 0s | Datos en AXI. | TEST OK        |

## Test 1
- Se envio un paquete IDLE con el caracter de inicio de paquete al final del mismo.
- Se enviaron paquetes equivalentes a 46 bytes de datos con todos 0s.
- Al finalizar se envio el delimitador de final de paquete junto con datos IDLE.

### Resultados Test 1

- En la interfaz AXI se recibieron los 46 bytes.
- Las señales indicadoras de inicio y final de paquete se activaron en el momento correspondiente.

![Test1](<img/Waveform-TEST1.png>)

## Test 2
- Se envio un paquete IDLE con el caracter de inicio de paquete al final del mismo.
- Se enviaron paquetes equivalentes a 1500 bytes de datos con todos 0s.
- Al finalizar se envio el delimitador de final de paquete junto con datos IDLE.

### Resultados Test 2

- En la interfaz AXI se recibieron los 1500 bytes, sin errores.
- Las señales indicadoras de inicio y final de paquete se activaron en el momento correspondiente.

![Test2](<img/Waveform-TEST2.png>)

## Test 3
- Se envio un paquete IDLE con el caracter de inicio de paquete al final del mismo.
- Se enviaron paquetes equivalentes a 45 bytes de datos igual a 10 y un byte de padding, es decir 0.
- Al finalizar se envio el delimitador de final de paquete junto con datos IDLE.

### Resultados Test 3

- En la interfaz AXI se recibieron los 45 bytes más el bit de padding. No hubo errores
- Las señales indicadoras de inicio y final de paquete se activaron en el momento correspondiente.

![Test3](<img/Waveform-TEST3.png>)

## Test 4
- Se envio un paquete IDLE con el caracter de inicio de paquete al final del mismo.
- Se enviaron paquetes equivalentes a 1501 bytes de datos con todos 0s.
- Al finalizar se envio el delimitador de final de paquete junto con datos IDLE.

### Resultados Test 4

- En la interfaz AXI se recibieron los 1501 bytes, incluso cuando esto significa que supera la máxima longitud defida por la norma.
- Las señales indicadoras de inicio y final de paquete se activaron en el momento correspondiente.

![Test4](<img/Waveform-TEST4.png>)
