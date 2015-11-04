package com.winel.test;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.MalformedURLException;
import java.net.URL;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

import javax.net.ssl.HttpsURLConnection;

import javassist.bytecode.ConstantAttribute;

public class EncryptComm {
	
	private final static String appIdString = "wx716b446c61d5641c";
	private final static String appSecretString = "b115cee7553d8b143afbc3a1116df96c";
	
	
	public static String getappkey(){
		return "feniownogbwoegwobg";
	}
	/**
	 * sha1 encrypt
	 * @param source string
	 * @return sha1 string
	 * @throws NoSuchAlgorithmException 
	 */
	public static String SHA1Encrypt(String SourceString) throws NoSuchAlgorithmException{
		MessageDigest mDigest = MessageDigest.getInstance("SHA1");
		byte[] result = mDigest.digest(SourceString.getBytes());
		StringBuffer sb = new StringBuffer();
		for(int i = 0; i < result.length; i++){
			sb.append(Integer.toString((result[i] & 0xff) + 0x100, 16).substring(1));
		}
		return sb.toString();
	}
	
	private static String inStream2String(InputStream is) throws Exception {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        byte[] buf = new byte[1024];
        int len = -1;
        while ((len = is.read(buf)) != -1) {
            baos.write(buf, 0, len);
        }
        return new String(baos.toByteArray());
    }
	/**
	 * get token
	 * @param appid
	 * @param appsecret
	 * @return token string
	 * @throws MalformedURLException 
	 */
	public static String GetAccessTokenStr() throws MalformedURLException{
		String urlString = "https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=" 
				+ appIdString + "&secret=" + appSecretString;
		try {
			URL url = new URL(urlString);
			HttpsURLConnection conn = (HttpsURLConnection)url.openConnection();
			conn.setRequestMethod("GET");
			InputStream inStream = conn.getInputStream();
			try {
				String msg = inStream2String(inStream);
				return msg;
			} catch (Exception e) {
				// TODO Auto-generated catch block
				e.printStackTrace();
			}
		} catch (IOException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		}
		return "";
	}

}
