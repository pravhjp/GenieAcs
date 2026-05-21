// Provision: inform
// Purpose: Set ACS URL, credentials, and inform interval on every device inform

//-------------------- ACS URL -----------------------------//
// IMPORTANT: Replace the IP below with your VPS public IP address
// Example: if your VPS IP is 103.45.67.89, set it as: "http://103.45.67.89:7547"
const url = "http://YOUR_VPS_IP:7547";

//--------------------- Inform Interval ----------------------------//
const informInterval = 200; // interval in seconds

const daily   = Date.now(86400000);
const minutes = Date.now(300000);
const update  = Date.now(60000);
const hourly  = Date.now(3590000);

const informTime = Date.now() % 86400000;

//-------------------- ACS Credentials ----------------------------//
// Username and password that devices use to authenticate with ACS
const AcsUser = "acs";
const AcsPass = "acsadmin12345";

//-------------------- Connection Request Credentials -------------//
// Username and password ACS uses to send connection requests to devices
let ConnReqUser = "acs";
const ConnReqPass = "acsadmin12345";

const brand = declare('DeviceID.Manufacturer', {value: daily}).value[0];

//-------------------- Apply Settings to Device -------------------//
if (brand !== "MikroTik") {
    // Standard ONT devices (Huawei, ZTE, FiberHome, etc.) -- TR-098 path
    declare("InternetGatewayDevice.ManagementServer.URL", {value: daily}, {value: url});
    declare("InternetGatewayDevice.ManagementServer.Username", {value: daily}, {value: AcsUser});
    declare("InternetGatewayDevice.ManagementServer.Password", {value: daily}, {value: AcsPass});
    declare("InternetGatewayDevice.ManagementServer.ConnectionRequestUsername", {value: update}, {value: ConnReqUser});
    declare("InternetGatewayDevice.ManagementServer.ConnectionRequestPassword", {value: update}, {value: ConnReqPass});
    declare("InternetGatewayDevice.ManagementServer.PeriodicInformEnable", {value: daily}, {value: true});
    declare("InternetGatewayDevice.ManagementServer.PeriodicInformInterval", {value: daily}, {value: informInterval});
} else {
    // MikroTik devices -- TR-181 path (Device.*)
    declare("Device.ManagementServer.URL", {value: daily}, {value: url});
    declare("Device.ManagementServer.Username", {value: daily}, {value: AcsUser});
    declare("Device.ManagementServer.Password", {value: daily}, {value: AcsPass});
    declare("Device.ManagementServer.ConnectionRequestUsername", {value: daily}, {value: ConnReqUser});
    declare("Device.ManagementServer.ConnectionRequestPassword", {value: daily}, {value: ConnReqPass});
    declare("Device.ManagementServer.PeriodicInformEnable", {value: daily}, {value: true});
    declare("Device.ManagementServer.PeriodicInformInterval", {value: daily}, {value: informInterval});
}
