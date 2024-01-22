# Script to enable TRIM on SSD

Step 1: Run `chmod +x trim.sh`
Step 2: Run `sudo ./trim.sh`

Based on the guide here https://www.jeffgeerling.com/blog/2020/enabling-trim-on-external-ssd-on-raspberry-pi

Note: Currently only works on SSD connected via the Homerun brand usb adapter. To get it to work on a different adapter, change the vendor id and product id in the code. In the future, I'd like to improve the script so that it prompts you on which adapter/drive you'd like to operate.
