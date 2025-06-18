#!/bin/bash

clear
echo "📲 Iniciando instalación del bot SSH para Telegram..."
read -p "🔑 Ingresa el TOKEN del bot de Telegram: " BOT_TOKEN
read -p "💳 Ingresa el ACCESS TOKEN de Mercado Pago: " MP_TOKEN
read -p "🌐 Ingresa el dominio (debe apuntar al servidor): " DOMINIO

# Planes personalizados
echo "📋 Define los planes:"
read -p "Duración (días) del Plan 1: " P1_DIAS
read -p "Precio del Plan 1: " P1_PRECIO
read -p "Duración (días) del Plan 2: " P2_DIAS
read -p "Precio del Plan 2: " P2_PRECIO
read -p "Duración (días) del Plan 3: " P3_DIAS
read -p "Precio del Plan 3: " P3_PRECIO

# Verificar puertos
echo "🔍 Verificando puertos..."
PORTS=(80 5000)
for PORT in "${PORTS[@]}"; do
  if lsof -i :$PORT &> /dev/null; then
    echo "⚠️ El puerto $PORT ya está en uso. Asegúrate de liberarlo si es necesario."
  else
    echo "✅ Puerto $PORT libre."
  fi
done

echo "📦 Actualizando sistema..."
sudo apt update && sudo apt upgrade -y

echo "🐍 Instalando dependencias..."
sudo apt install -y python3 python3-pip python3-venv git unzip curl

echo "📁 Preparando entorno del bot..."
mkdir -p ~/bot_ssh && cd ~/bot_ssh
python3 -m venv venv
source venv/bin/activate

pip install --upgrade pip
pip install aiogram==2.25.2 mercadopago qrcode[pil] flask requests

cat > config.py <<EOF
TELEGRAM_BOT_TOKEN="${BOT_TOKEN}"
MERCADO_PAGO_ACCESS_TOKEN="${MP_TOKEN}"
DOMINIO="${DOMINIO}"
EOF

cat > plans.json <<EOF
[
  {"dias": $P1_DIAS, "precio": $P1_PRECIO},
  {"dias": $P2_DIAS, "precio": $P2_PRECIO},
  {"dias": $P3_DIAS, "precio": $P3_PRECIO}
]
EOF

cat > entrega.py <<EOF
accesos_ssh = [
    {"user": "Gabriel", "pass": "6197", "limit": 1},
    {"user": "Juan", "pass": "2345", "limit": 1},
    {"user": "Maria", "pass": "8821", "limit": 1}
]

def entregar_acceso():
    if accesos_ssh:
        return accesos_ssh.pop(0)
    return None
EOF

cat > bot.py <<'EOF'
import logging
from aiogram import Bot, Dispatcher, executor, types
import json
import qrcode
import io
import mercadopago
from config import TELEGRAM_BOT_TOKEN, MERCADO_PAGO_ACCESS_TOKEN

logging.basicConfig(level=logging.INFO)
bot = Bot(token=TELEGRAM_BOT_TOKEN)
dp = Dispatcher(bot)
sdk = mercadopago.SDK(MERCADO_PAGO_ACCESS_TOKEN)

with open('plans.json', 'r') as f:
    PLANS = json.load(f)

@dp.message_handler(commands=['start'])
async def start(msg: types.Message):
    keyboard = types.InlineKeyboardMarkup(row_width=1)
    for i, plan in enumerate(PLANS):
        keyboard.add(types.InlineKeyboardButton(
            text=f"{plan['dias']} días - \${plan['precio']}",
            callback_data=f"comprar_{i}"
        ))
    await msg.answer("🔥 *Planes SSH Disponibles:*\n\nElige uno de los siguientes planes:",
                     parse_mode="Markdown", reply_markup=keyboard)

@dp.callback_query_handler(lambda call: call.data.startswith("comprar_"))
async def comprar_callback(call: types.CallbackQuery):
    idx = int(call.data.split("_")[1])
    plan = PLANS[idx]

    payment_data = {
        "transaction_amount": float(plan["precio"]),
        "description": f"SSH {plan['dias']} días",
        "payment_method_id": "pix",
        "payer": {"email": f"user{call.from_user.id}@mail.com"}
    }

    result = sdk.payment().create(payment_data)
    payment = result["response"]
    link = payment["point_of_interaction"]["transaction_data"]["ticket_url"]

    qr = qrcode.make(link)
    bio = io.BytesIO()
    qr.save(bio, format='PNG')
    bio.seek(0)

    await call.message.answer(
        f"💳 *Paga \${plan['precio']} por {plan['dias']} días de SSH:*\n\n🔗 {link}",
        parse_mode="Markdown"
    )
    await call.message.answer_photo(photo=bio, caption="📸 Escanea para pagar via QR PIX (Mercado Pago)")
EOF

cat > webhook.py <<'EOF'
from flask import Flask, request
import mercadopago
import requests
from entrega import entregar_acceso
from config import MERCADO_PAGO_ACCESS_TOKEN, TELEGRAM_BOT_TOKEN
import datetime
import json

app = Flask(__name__)
sdk = mercadopago.SDK(MERCADO_PAGO_ACCESS_TOKEN)

with open('plans.json', 'r') as f:
    PLANS = json.load(f)

@app.route("/webhook", methods=["POST"])
def webhook():
    data = request.get_json()
    if data and "data" in data and "id" in data["data"]:
        payment_id = data["data"]["id"]
        payment = sdk.payment().get(payment_id)["response"]

        if payment["status"] == "approved":
            email = payment["payer"]["email"]
            user_id = email.split("@")[0].replace("user", "")
            descripcion = payment["description"]
            dias = next((p["dias"] for p in PLANS if str(p["dias"]) in descripcion), 7)
            hoy = datetime.datetime.now()
            vencimiento = (hoy + datetime.timedelta(days=dias)).strftime("%d-%m-%Y")

            acceso = entregar_acceso()
            if acceso:
                msg = (
                    "✅ PAGO CONFIRMADO !\n\n"
                    "🧩ACCESO CREADO CON EXITO ✅\n\n"
                    f"👤USUARIO: {acceso['user']}\n"
                    f"🔐CONTRASEÑA: {acceso['pass']}\n"
                    f"📲LIMITE: {acceso['limit']}\n"
                    f"🗓️VENCIMIENTO: {vencimiento}\n\n"
                    "📥 APLICACION: https://play.google.com/store/apps/details?id=app.conecta.pro"
                )
            else:
                msg = "⚠️ PAGO CONFIRMADO pero no hay accesos disponibles."

            url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
            payload = {
                "chat_id": int(user_id),
                "text": msg
            }
            requests.post(url, json=payload)
    return "OK", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

echo ""
echo "✅ Instalación completada."
echo ""
echo "👉 Inicia el bot con:"
echo "   cd ~/bot_ssh && source venv/bin/activate && python3 bot.py"
echo ""
echo "👉 Inicia el webhook con:"
echo "   python3 webhook.py"
echo ""
echo "⚠️ Asegúrate de que los puertos 80 y 5000 estén abiertos en tu VPS"
