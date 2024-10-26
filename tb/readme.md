# Descripción de los test realizados

## Test sobre el receptor

Se realizaron test para comprobar el correcto funcionamiento del procesamiento de datos por parte del receptor. Estos se encuentran en el archivo [test RX](eth_mac_10g_rx_tb.v).

## Test 1
- Se envio un paquete con caracter XGMII de inicio, Preambulo y SFD.
- Se enviaron 6 bytes de dirección de destino, otros 6 de dirección de fuente, y 2 bytes de tamaño de paquete.
- Se enviaron paquetes equivalentes a 46 bytes de datos con el valor "06".
- Se colocó el checksum correspondiente al final de la carga util de datos.
- Al finalizar se envió el delimitador de final de paquete XGMII, y luego datos IDLE.

### Resultados Test 1

- En la interfaz AXI se recibió el Preambulo, SFD, los bytes 46 datos y el checksum.
- La interfaz AXI solo corta los caracteres XGMII reemplazandolos por "00".
- No se detectaron errores.
![image](https://github.com/user-attachments/assets/f9f64696-c672-46ca-8768-3ebe33b10fc1)

## Test 2
- Se envio un paquete con caracter XGMII de inicio, Preambulo y SFD.
- Se enviaron 6 bytes de dirección de destino, otros 6 de dirección de fuente, y 2 bytes de tamaño de paquete.
- Se enviaron paquetes equivalentes a 45 bytes de datos con el valor "06".
- Se colocó el checksum correspondiente al final de la carga util de datos.
- Al finalizar se envió el delimitador de final de paquete XGMII, y luego datos IDLE.

### Resultados Test 2

- En la interfaz AXI se recibió el Preambulo, SFD, los 45 bytes de datos y el checksum.
- La interfaz AXI solo corta los caracteres XGMII reemplazandolos por "00".
- No se presentan errores, a pesar de que el tamaño del paquete es más chico que lo estipulado por la norma
![image](https://github.com/user-attachments/assets/8a3c5c52-d5ea-4da0-a746-677341e2c811)

![image](https://github.com/user-attachments/assets/2ecd9f79-6e79-49aa-888d-823593bdad8c)

## Test 3
- Se envio un paquete con caracter XGMII de inicio, Preambulo y SFD.
- Se enviaron 6 bytes de dirección de destino, otros 6 de dirección de fuente, y 2 bytes de tamaño de paquete.
- Se enviaron paquetes equivalentes a 45 bytes de datos con el valor "06" + 1 byte de padding, es decir, "00".
- Se colocó el checksum correspondiente al final de la carga util de datos.
- Al finalizar se envió el delimitador de final de paquete XGMII, y luego datos IDLE.

### Resultados Test 3

- En la interfaz AXI se recibió el Preambulo, SFD, los 45 bytes de datos, el byte de padding y el checksum.
- La interfaz AXI solo corta los caracteres XGMII reemplazandolos por "00".
- No hubo errores.
![image](https://github.com/user-attachments/assets/f3c3a1d1-b966-4649-baf3-cf86ca24033c)


## Test 4
- Se envio un paquete con caracter XGMII de inicio, Preambulo y SFD.
- Se enviaron 6 bytes de dirección de destino, otros 6 de dirección de fuente, y 2 bytes de tamaño de paquete.
- Se enviaron paquetes equivalentes a 10 bytes de datos con el valor "06".
- Se colocó el checksum correspondiente al final de la carga util de datos.
- Al finalizar se envió el delimitador de final de paquete XGMII, y luego datos IDLE.

### Resultados Test 4

- En la interfaz AXI se recibió el Preambulo, SFD, los 10 bytes de datos y el checksum.
- La interfaz AXI solo corta los caracteres XGMII reemplazandolos por "00".
- Aunque el tamaño del paquete es considerablemente más chico que lo que indica la norma, no hubo errores.
![image](https://github.com/user-attachments/assets/593f015d-c021-4e67-926f-cbe7b27b902d)


## Test 5
- Se envio un paquete con caracter XGMII de inicio, Preambulo y SFD.
- Se enviaron 6 bytes de dirección de destino, otros 6 de dirección de fuente, y 2 bytes de tamaño de paquete.
- Se enviaron paquetes equivalentes a 1500 bytes de datos con el valor "06".
- Se colocó el checksum correspondiente al final de la carga util de datos.
- Al finalizar se envió el delimitador de final de paquete XGMII, y luego datos IDLE.

### Resultados Test 5

- En la interfaz AXI se recibió el Preambulo, SFD, los 1500 bytes de datos y el checksum.
- La interfaz AXI solo corta los caracteres XGMII reemplazandolos por "00".
- Como era esperado, no se presentaron errores.
![image](https://github.com/user-attachments/assets/650ebac2-8e77-4c81-9161-5c3971764ec7)

## Test 6
- Se envio un paquete con caracter XGMII de inicio, Preambulo y SFD.
- Se enviaron 6 bytes de dirección de destino, otros 6 de dirección de fuente, y 2 bytes de tamaño de paquete.
- Se enviaron paquetes equivalentes a 1501 bytes de datos con el valor "06".
- Se colocó el checksum correspondiente al final de la carga util de datos.
- Al finalizar se envió el delimitador de final de paquete XGMII, y luego datos IDLE.

### Resultados Test 6

- En la interfaz AXI se recibió el Preambulo, SFD, los 1501 bytes de datos y el checksum.
- La interfaz AXI solo corta los caracteres XGMII reemplazandolos por "00".
- No se presentaron errores.


