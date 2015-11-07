package com.winel.test;

import java.io.IOException;
import java.io.PrintWriter;
import java.security.NoSuchAlgorithmException;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Arrays;
import java.util.Map;

import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.apache.log4j.Logger;


/**
 * Servlet implementation class TestServlet
 */
@WebServlet(description = "test", 
	urlPatterns = { "/testServlet",
					"/gettoken"})
public class TestServlet extends HttpServlet {
	
	private Logger log = Logger.getLogger(TestServlet.class);
	private static final long serialVersionUID = 1L;
       
    /**
     * @see HttpServlet#HttpServlet()
     */
    public TestServlet() {
        super();
        // TODO Auto-generated constructor stub
    }

	/**
	 * @see HttpServlet#doGet(HttpServletRequest request, HttpServletResponse response)
	 */
	protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
		// TODO Auto-generated method stub
		synchronized (this){	
			PrintWriter pwWriter = response.getWriter();
			//消息验证
			if(request.getServletPath().equals("/testServlet")){
				String signString = request.getParameter("signature");
				String timeString = request.getParameter("timestamp");
				String nonceString = request.getParameter("nonce");
				String echoString = request.getParameter("echostr");
				String[] arr = new String[]{EncryptComm.getTOKEN_STRING(), timeString, nonceString};
				Arrays.sort(arr);
				StringBuilder sbuBuilder = new StringBuilder();
				for(String temp: arr){
					sbuBuilder.append(temp);
				}
				String comparestr;
				try {
					comparestr = EncryptComm.SHA1Encrypt(sbuBuilder.toString());
					if(signString.equals(comparestr)){
						pwWriter.println(echoString);
					}else{
						pwWriter.println("Error!");
					}
				} catch (NoSuchAlgorithmException e) {
					// TODO Auto-generated catch block
					e.printStackTrace();
				}	
			}else if(request.getServletPath().equals("/gettoken")){
				try {
					pwWriter.println(EncryptComm.GetAccessTokenStr());
				} catch (SQLException e) {
					// TODO Auto-generated catch block
					e.printStackTrace();
				}
			}			
			pwWriter.flush();
			pwWriter.close();
		}
	}

	/**
	 * @see HttpServlet#doPost(HttpServletRequest request, HttpServletResponse response)
	 */
	protected void doPost(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
		// TODO Auto-generated method stub
	}

}
