#!/bin/bash

echo "🔐 Ingresá el token de tu bot de Telegram:"
read -p "👉 TELEGRAM_BOT_TOKEN: " BOT_TOKEN

echo "💳 Ingresá tu Access Token de Mercado Pago:"
read -p "👉 MERCADO_PAGO_ACCESS_TOKEN: " MP_TOKEN

echo "📦 Actualizando sistema..."
sudo apt update && sudo apt upgrade -y

echo "🐍 Instalando Python y dependencias..."
sudo apt install -y python3 python3-pip python3-venv git unzip curl

echo "📁 Creando entorno del bot..."
mkdir -p ~/bot_ssh && cd ~/bot_ssh
python3 -m venv venv
source venv/bin/activate

pip install --upgrade pip
pip install aiogram mercadopago qrcode[pil] flask requests

cat > config.py <<EOF
TELEGRAM_BOT_TOKEN="${BOT_TOKEN}"
MERCADO_PAGO_ACCESS_TOKEN="${MP_TOKEN}"
EOF

cat > plans.json <<EOF
[
  {"dias": 8, "precio": 10},
  {"dias": 16, "precio": 15},
  {"dias": 31, "precio": 20}
]
EOF

cat > entrega.py <<EOF
accesos_ssh = [
    {"host": "ssh1.tuservidor.com", "user": "user1", "pass": "123456", "limit": 1},
    {"host": "ssh2.tuservidor.com", "user": "user2", "pass": "abcdef", "limit": 1}
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
            vencimiento = (hoy + datetime.timedelta(days=dias)).strftime("%d/%m/%Y")

            acceso = entregar_acceso()
            if acceso:
                msg = (
                    f"✅ *Pago confirmado*\n\n"
                    f"🧩 *Acceso Creado:*\n"
                    f"👤Usuario: `{acceso['user']}`\n"
                    f"🔐Clave: `{acceso['pass']}`\n"
                    f"📲Límite: {acceso.get('limit', 1)}\n"
                    f"🗓️Vencimiento: {vencimiento}\n\n"
                    f"📥 Descarga nuestra app desde la PlayStore:\n"
                    f"[Conecta HTTP](https://play.google.com/store/apps/details?id=app.conecta.pro)"
                )
            else:
                msg = "⚠️ *Pago confirmado pero no hay accesos SSH disponibles.*"

            url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
            payload = {
                "chat_id": int(user_id),
                "text": msg,
                "parse_mode": "Markdown"
            }
            requests.post(url, json=payload)
    return "OK", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

echo ""
echo "✅ Instalación completada."
echo ""
echo "👉 Para iniciar el bot:"
echo "   cd ~/bot_ssh && source venv/bin/activate"
echo "   python3 bot.py"
echo ""
echo "👉 Para iniciar el webhook:"
echo "   python3 webhook.py"
echo ""
echo "⚠️ Recordá exponer el puerto 5000 usando ngrok u otro túnel:"
echo "   ./ngrok http 5000"
