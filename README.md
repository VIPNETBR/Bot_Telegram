# 🤖 Bot Telegram SSH + PIX (Mercado Pago)

Este bot permite vender accesos SSH automáticamente mediante pagos vía **PIX (Mercado Pago)**. Al confirmar el pago, el bot entrega automáticamente al usuario un acceso SSH y un mensaje personalizado.

---

## 🚀 Funcionalidades

- 📦 Venta de planes SSH con días configurables
- 💳 Pago vía PIX usando Mercado Pago
- ✅ Entrega automática de accesos tras el pago
- 🧩 Formato claro con datos de conexión
- 📲 Botones inline para comprar planes
- 🌐 Webhook para confirmación automática del pago

---

## 📁 Estructura del Proyecto

```
Bot_Telegram/
├── bot.py             # Bot de Telegram con Aiogram
├── webhook.py         # Servidor Flask que maneja confirmación de pagos
├── config.py          # Tokens y configuraciones
├── entrega.py         # Lista de accesos SSH disponibles
├── plans.json         # Planes de días/precio
├── instalar_bot_ssh.sh# Script de instalación automatizada
├── ngrok.service      # Servicio systemd opcional para ngrok
├── requirements.txt   # Dependencias Python
└── .gitignore         # Archivos a ignorar por Git
```

---

## 🛠️ Instalación rápida (VPS)

```bash
bash <(curl -s https://raw.githubusercontent.com/VIPNETBR/Bot_Telegram/main/instalar_bot_ssh.sh)
```

---

## 📦 Requisitos

- VPS con Ubuntu 20.04 o superior
- Python 3
- Token de Mercado Pago con acceso a PIX
- Bot de Telegram creado (con su token)

---

## ⚙️ Ejecutar

1. Activar entorno:

```bash
source ~/bot_ssh/venv/bin/activate
```

2. Iniciar el bot:

```bash
python3 bot.py
```

3. Iniciar el webhook (si no usas Gunicorn o Nginx):

```bash
python3 webhook.py
```

4. Exponer el puerto:

```bash
ngrok http 5000
```

---

## 📲 App recomendada

Puedes sugerir al usuario final descargar tu app:

```
📥 Descarga nuestra aplicación desde la PlayStore “Conecta HTTP”

https://play.google.com/store/apps/details?id=app.conecta.pro
```

---

## 📬 Contacto

Creado por [VIPNETBR](https://github.com/VIPNETBR)

---
