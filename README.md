# GenieAcs
GenieAcs Install on Ubuntu 22.04 LTS

1. Put this in root : install-genieacs.sh
2. chmod +x install-genieacs.sh
3. bash install-genieacs.sh

# GenieAcsProvision.js - Where and How to use It

1. Open in a browser: http://YOUR_VPS_IP:3000
2. Log in with your admin credentials
3. Click Admin in the top menu
4. Click Provisions on the left side
5. Click on the inform row in the list
6. Select (Ctrl+A) and delete any old code that appears there.
7. Paste the entire contents of the provision_inform.js file there.
8. Change just this one line inside it—enter your VPS IP:
jsconst url = "http://YOUR_VPS_IP:7547";
9. Press Save button - it's done ✅
This provision will automatically set ACS URL, credentials and interval on every device's notification.
