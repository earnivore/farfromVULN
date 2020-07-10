from flask import *
import json
import subprocess
app = Flask(__name__)

@app.route('/')
def index():
    f = open('instance_ips.txt', 'r')
    data = json.load(f)

    vpn_ip = data['PiVPN'].get('value')
    kali_ip = data['Kali'].get('value')

    vulns = []

    # Find the vulnerable machine
    for machine_name in data:
        if "Vulnhub" in machine_name:
            mini_list = [machine_name, data[machine_name].get('value')]
            vulns.append(mini_list)

    
    return render_template('index_template.html', vpn_ip=vpn_ip, kali_ip=kali_ip, vulns=vulns)

@app.route('/images/<image>')
def get_image(image=None):
    return send_file('images/' + image, mimetype='png')

@app.route('/faq.html')
def get_faq():
    return send_file('faq.html')

@app.route('/<name>')
def get_vpn(name=None):
    cmd = "pivpn -a -n " + name + " nopass -d 1000"
    process = subprocess.Popen(cmd.split(), stdout=subprocess.PIPE)
    output, error = process.communicate()

    app.logger.debug(output)
    app.logger.warning(error)

    ovpn_file = send_from_directory('/home/ubuntu/ovpns/', filename = name + '.ovpn', as_attachment = True)
    return ovpn_file



    
