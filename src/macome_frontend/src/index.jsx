import * as React from "react";
import { useState, useEffect, useRef } from "react";
import { render } from "react-dom";
import { Principal } from "@dfinity/principal";
import { AuthClient } from "@dfinity/auth-client";
import { Actor, HttpAgent } from "@dfinity/agent";

import { idlFactory } from "./asset.did";




const App = () => {
  const db1 = "dcbce-3yaaa-aaaag-qb5vq-cai";
  // const db2 = "sr335-fiaaa-aaaak-qb72a-cai";
  const asset = "sr335-fiaaa-aaaak-qb72a-cai";

  const [connect, setConnect] = useState("");
  const [address, setAddress] = useState("");
  const [identity, setIdentity] = useState(null);
  const [loader, setLoader] = useState(false);

  const [base64, setBase64] = useState("");

  const [ready, setReady] = useState(false);
  const [filesData, setFilesData] = useState([]);

  const [name, setName] = useState("");
  const [file, setFile] = useState([]);

  const [_type, setType] = useState("");

  useEffect(() => {
    async function checkConnection() {
      if (identity == null) {
        let i = await nfidConnect();
        let p = i.getPrincipal();
        setAddress(p.toString());
        setIdentity(i);
        // console.log(Principal.toSring(i.getPrincipal()));
        setConnect("Connected!");
      } else {
        // console.log(Principal.toSring(i.getPrincipal()));
        setConnect("Connected!");
      }
    }
    checkConnection();
  }, []);

  const nfidConnect = async (event) => {
    const APPLICATION_NAME = "MACOME";
    const APPLICATION_LOGO_URL = "";
    const APP_META = `applicationName=RequestTransfer&applicationLogo=${APPLICATION_LOGO_URL}`;
    const AUTH_PATH = "/authenticate/?applicationName=" + APPLICATION_NAME + "#authorize";
    const NFID_AUTH_URL = "https://nfid.one" + AUTH_PATH;
    const NFID_ORIGIN = "https://nfid.one";
    const REQ_TRANSFER = "wallet/request-transfer";

    const authClient = await AuthClient.create();
    if (await authClient.isAuthenticated()) {
      return authClient.getIdentity();
    }
    await new Promise((resolve, reject) => {
      authClient.login({
        identityProvider: NFID_AUTH_URL,
        windowOpenerFeatures:
          `left=${window.screen.width / 2 - 525 / 2}, ` +
          `top=${window.screen.height / 2 - 705 / 2},` +
          `toolbar=0,location=0,menubar=0,width=525,height=705`,
        onSuccess: resolve,
        onError: reject,
      });
    });
    let identity = authClient.getIdentity();
    // setIdentity(identity);
    return identity;
  };

  const wallet_connect = async (event) => {
    const APPLICATION_NAME = "MACOME";
    const APPLICATION_LOGO_URL = "";
    const APP_META = `applicationName=RequestTransfer&applicationLogo=${APPLICATION_LOGO_URL}`;
    const AUTH_PATH = "/authenticate/?applicationName=" + APPLICATION_NAME + "#authorize";
    const NFID_AUTH_URL = "https://nfid.one" + AUTH_PATH;
    const NFID_ORIGIN = "https://nfid.one";
    const REQ_TRANSFER = "wallet/request-transfer";

    const authClient = await AuthClient.create();
    // if (await authClient.isAuthenticated()) {
    //   return authClient.getIdentity();
    // }
    await new Promise((resolve, reject) => {
      authClient.login({
        identityProvider: NFID_AUTH_URL,
        windowOpenerFeatures:
          `left=${window.screen.width / 2 - 525 / 2}, ` +
          `top=${window.screen.height / 2 - 705 / 2},` +
          `toolbar=0,location=0,menubar=0,width=525,height=705`,
        onSuccess: resolve,
        onError: reject,
      });
    });
    let identity = authClient.getIdentity();
    return identity;
  };

  const trim_folder_name = (name) => {
    let res = "";
    let index = "";
    for (let i = 0; i < name.length; i++) {
      if (name[i] == "/") {
        index = i;
        break;
      }
    }
    for (let i = index; i < name.length; i++) {
      res = res + name[i];
    }
    return res;
  };

  const reverse = (str) => {
    return str.split("").reverse().join("");
  }

  const b64toArrays = (base64) => {
    let encoded = base64.toString().replace(/^data:(.*,)?/, '');
    if ((encoded.length % 4) > 0) {
      encoded += '='.repeat(4 - (encoded.length % 4));
    }
    setBase64(encoded);
    const byteCharacters = Buffer.from(encoded, 'base64');
    const byteArrays = [];
    const sliceSize = 1500000;
    // const sliceSize = 15000;

    for (let offset = 0; offset < byteCharacters.length; offset += sliceSize) {
      const byteArray = [];
      let x = offset + sliceSize;
      if (byteCharacters.length < x) {
        x = byteCharacters.length;
      }
      for (let i = offset; i < x; i++) {
        byteArray.push(byteCharacters[i]);
      }
      byteArrays.push(byteArray);
    }
    return byteArrays;
  }

  const b64toType = (base64) => {
    let type = "";
    let encode = base64.toString();
    let f = false;
    for (let i = 0; i < encode.length; i++) {
      if (encode[i] == ":") {
        f = true;
      } else if (f & encode[i] != ";") {
        type += encode[i];
      }
      if (encode[i] == ";") {
        break;
      }
    }
    return type;
  };

  //To upload File : Testing
  const uploadFiles = async () => {
    if (identity == null) {
      alert("Connect NFID!");
      return;
    }
    const agent = new HttpAgent({
      identity: identity,
      host: "https://ic0.app/",
    });
    const actor = Actor.createActor(idlFactory, {
      agent,
      canisterId: asset,
    });

    // const actor2 = Actor.createActor(idlFactory, {
    //   agent,
    //   canisterId: db2,
    // });

    try {
      setLoader(true);
      const chunks = [];
      const res1 = await actor.create_batch();
      console.log(res1);
      for (let i = 0; i < file.length; i++) {
        console.log(file[i]);
        const _req2 = {
          content: file[i],
          batch_id: Number(res1.batch_id),
        };
        const res2 = await actor.create_chunk(_req2);
        console.log(res2);
        chunks.push(Number(res2.chunk_id));
      }
      console.log(chunks);
      var _name = "/" + name;
      const etag = Math.random();
      console.log(_type);
      await actor.commit_asset_upload(res1.batch_id, String(_name), String(_type), chunks, "identity", etag.toString());
      console.log("uploaded!");
      setLoader(false);
    }
    catch (err) {
      alert(err);
      setLoader(false)
    }
  };

  const handleUpload = (event) => {
    setReady(false);
    const file = event.target.files[0];
    console.log(file);
    let fileName = "";
    let fileType = "";
    let fileArr = [];
    // Make new FileReader
    const reader = new FileReader();
    // Convert the file to base64 text
    reader.readAsDataURL(file);
    reader.onloadend = () => {
      let encoded = reader.result.toString().replace(/^data:(.*,)?/, '');
      if ((encoded.length % 4) > 0) {
        encoded += '='.repeat(4 - (encoded.length % 4));
      }
      fileArr = b64toArrays(reader.result);
      fileType = b64toType(reader.result);
      fileName = file.name;
      console.log(fileName + ' | ' + Math.round(file.size) + ' Bytes');
      console.log(fileArr);
      setFile(fileArr);
      setName(fileName);
      setType(fileType);
      setReady(true);
    };
    setReady(true);
  };

  return (
    <div style={{ "fontSize": "30px" }}>
      <div style={{ "display": "flex", "justifyContent": "center", "position": "fixed", backgroundColor: "black", color: "white", width: "100%" }}>
        {/* <div style={{ marginRight: 50 }}>
          {
            loader && (<Audio
              height="30"
              width="30"
              radius="9"
              color='green'
              ariaLabel='three-dots-loading'
              wrapperStyle
              wrapperClass
            />)
          }
        </div> */}
        <div>
          <button
            style={{ backgroundColor: "", cursor: 'pointer', marginTop: 20, marginBottom: 20, width: 150, height: 30 }}
            className=""
            onClick={wallet_connect}>
            Connect NFID
          </button>
        </div>
        <div style={{ alignText: "center", paddingTop: "15px", paddingLeft: "20px" }}>{address}</div>
      </div>
      <br></br>
      <br></br>
      <br></br>
      <div>
        Upload Folder:
        <div>
          <div className="drag-text">
            <input type="file" onChange={handleUpload} />
          </div>
          {!!ready &&
            <button className="file-upload-btn" type="button" onClick={uploadFiles} >Upload</button>
          }
        </div>
      </div>
    </div>
  );
};

render(<App />, document.getElementById("app"));