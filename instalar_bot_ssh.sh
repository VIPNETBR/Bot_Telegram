#!/bin/bash

set -e

# Pedir datos al usuario
read -p "🔑 Ingresa el TOKEN del BOT Telegram: " BOT_TOKEN
read -p "🔑 Ingresa el ACCESS TOKEN de MercadoPago: " MP_TOKEN
read -p "🌐 Ingresa tu dominio tipo A (o IP vinculada): " DOMINIO

echo "📦 Actualizando sistema..."
sudo apt update && sudo apt upgrade -y

echo "🐍 Instalando Python y dependencias..."
sudo apt install -y python3 python3-pip python3-venv git curl unzip

echo "📁 Preparando entorno bot_ssh..."
mkdir -p ~/bot_ssh && cd ~/bot_ssh
python3 -m venv venv
source venv/bin/activate

echo "⬇️ Instalando librerías Python necesarias..."
pip install --upgrade pip
pip install aiogram mercadopago qrcode[pil] flask requests

# Crear config.py
cat > config.py <<EOF
TELEGRAM_BOT_TOKEN = "${BOT_TOKEN}"
MERCADO_PAGO_ACCESS_TOKEN = "${MP_TOKEN}"
DOMINIO = "${DOMINIO}"
EOF

# Crear plans.json con los 3 planes fijos
cat > plans.json <<EOF
[
  {"dias": 31, "precio": 20},
  {"dias": 16, "precio": 15},
  {"dias": 8, "precio": 10}
]
EOF

# Archivo entrega.py con accesos SSH (ejemplo, editar después)
cat > entrega.py <<EOF
accesos_ssh = [
    {"host": "ssh1.tuservidor.com", "user": "Gabriel", "pass": "6197", "limit": 1},
    {"host": "ssh2.tuservidor.com", "user": "Lucas", "pass": "8754", "limit": 1}
]

def entregar_acceso():
    if accesos_ssh:
        return accesos_ssh.pop(0)
    return None
EOF

# Bot Telegram
cat > bot.py <<'EOF'
import logging
from aiogram import Bot, Dispatcher, types
from aiogram.utils import executor
import qrcode
from io import BytesIO
import mercadopago
import json
import threading
from config import TELEGRAM_BOT_TOKEN, MERCADO_PAGO_ACCESS_TOKEN

logging.basicConfig(level=logging.INFO)

bot = Bot(token=TELEGRAM_BOT_TOKEN)
dp = Dispatcher(bot)

sdk = mercadopago.SDK(MERCADO_PAGO_ACCESS_TOKEN)

with open("plans.json", "r") as f:
    PLANS = json.load(f)

def generar_qr(data: str) -> BytesIO:
    import qrcode
    from io import BytesIO
    qr = qrcode.QRCode(version=1, box_size=10, border=4)
    qr.add_data(data)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    bio = BytesIO()
    bio.name = "pix.png"
    img.save(bio, "PNG")
    bio.seek(0)
    return bio

@dp.message_handler(commands=["start"])
async def start_handler(message: types.Message):
    keyboard = types.InlineKeyboardMarkup(row_width=1)
    for i, plan in enumerate(PLANS):
        keyboard.add(types.InlineKeyboardButton(
            text=f"{plan['dias']} días - ${plan['precio']}",
            callback_data=f"comprar_{i}"
        ))
    await message.answer("🔥 *Planes SSH Disponibles:*\n\nElige uno para generar el pago:", parse_mode="Markdown", reply_markup=keyboard)

@dp.callback_query_handler(lambda c: c.data and c.data.startswith("comprar_"))
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

    pix_code = payment.get("point_of_interaction", {}).get("transaction_data", {}).get("qr_code")
    ticket_url = payment.get("point_of_interaction", {}).get("transaction_data", {}).get("ticket_url")

    if not pix_code or not ticket_url:
        await call.message.answer("❌ Error generando el pago, por favor intenta más tarde.")
        return

    qr_img = generar_qr(pix_code)

    texto_pago = (
        "✅ PAGAMENTO GERADO COM SUCESSO\n\n"
        "PIX COPIA E COLA:\n"
        f"{pix_code}\n\n"
        f"URL DO TICKET:\n{ticket_url}"
    )

    await call.message.answer_photo(photo=qr_img, caption=texto_pago)
    await call.answer()

if __name__ == "__main__":
    executor.start_polling(dp)
EOF

# webhook.py para confirmar pagos y entregar accesos
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
            user_id_str = email.split("@")[0].replace("user", "")
            try:
                user_id = int(user_id_str)
            except:
                return "User ID invalido", 400

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
                    f"📲LIMITE: {acceso.get('limit', 1)}\n"
                    f"🗓️VENCIMIENTO: {vencimiento}\n\n"
                    "📥 APLICACION: https://play.google.com/store/apps/details?id=app.conecta.pro"
                )
            else:
                msg = "⚠️ *Pago aprobado, pero no hay accesos SSH disponibles.*"

            url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
            payload = {
                "chat_id": user_id,
                "text": msg,
                "parse_mode": "Markdown"
            }
            requests.post(url, json=payload)

    return "OK", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

# Menú sencillo para administrar el bot
cat > menu.sh <<'EOF'
#!/bin/bash
source ~/bot_ssh/venv/bin/activate
cd ~/bot_ssh

while true; do
    clear
    echo "===== Menú de Administración Bot SSH ====="
    echo "1) Iniciar Bot Telegram"
    echo "2) Detener Bot Telegram"
    echo "3) Iniciar Webhook"
    echo "4) Detener Webhook"
    echo "5) Ver estado (procesos)"
    echo "6) Editar planes"
    echo "7) Ver ventas (logs de webhook)"
    echo "8) Desinstalar todo"
    echo "9) Salir"
    echo "=========================================="
    read -p "Elige opción: " opt

    case $opt in
        1)
            pkill -f bot.py || true
            nohup python3 bot.py > bot.log 2>&1 &
            echo "Bot iniciado."
            sleep 2
            ;;
        2)
            pkill -f bot.py && echo "Bot detenido." || echo "Bot no estaba corriendo."
            sleep 2
            ;;
        3)
            pkill -f webhook.py || true
            nohup python3 webhook.py > webhook.log 2>&1 &
            echo "Webhook iniciado."
            sleep 2
            ;;
        4)
            pkill -f webhook.py && echo "Webhook detenido." || echo "Webhook no estaba corriendo."
            sleep 2
            ;;
        5)
            echo "Procesos bot y webhook:"
            pgrep -fl bot.py
            pgrep -fl webhook.py
            read -p "Enter para continuar..."
            ;;
        6)
            nano plans.json
            ;;
        7)
            echo "Logs webhook:"
            tail -n 50 webhook.log
            read -p "Enter para continuar..."
            ;;
        8)
            read -p "¿Seguro quieres desinstalar todo? (s/n): " yn
            if [[ "$yn" == "s" ]]; then
                pkill -f bot.py || true
                pkill -f webhook.py || true
                rm -rf ~/bot_ssh
                echo "Desinstalado."
                exit 0
            fi
            ;;
        9)
            exit 0
            ;;
        *)
            echo "Opción inválida."
            sleep 1
            ;;
    esac
done
EOF
chmod +x menu.sh

echo ""
echo "✅ Instalación completa!"
echo "👉 Usa el script 'menu.sh' para administrar el bot y webhook"
echo "👉 Recuerda abrir los puertos 80 y 5000 en tu VPS (5000 para webhook)"
echo "   Si el puerto 80 está ocupado, el webhook usa el 5000."
echo ""
echo "Para comenzar:"
echo "  cd ~/bot_ssh && source venv/bin/activate && python3 bot.py"
echo "En otro terminal o con screen/tmux:"
echo "  cd ~/bot_ssh && source venv/bin/activate && python3 webhook.py"
echo ""
echo "O simplemente ejecuta ./menu.sh para controlarlo todo."
