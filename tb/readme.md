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

