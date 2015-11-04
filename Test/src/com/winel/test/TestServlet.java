package com.winel.test;

import java.io.IOException;
import java.io.PrintWriter;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.logging.Logger;

import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;


/**
 * Servlet implementation class TestServlet
 */
@WebServlet(description = "test", urlPatterns = { "/testServlet" })
public class TestServlet extends HttpServlet {
	
	private Logger log = Logger.getLogger(TestServlet.class.getName());
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
			String driverClass="com.mysql.jdbc.Driver";  
		    String url="jdbc:mysql://123.57.229.6:3306/mysql";//数据库主机地址以及数据库名     
		    String user="root";//MySQ帐号     
		    String password="ZHoiun89825";//MYSQL密码  
		    Connection conn = null;
		    try {
		    	Class.forName(driverClass).newInstance();
		    	conn = DriverManager.getConnection(url, user, password);
		    	Statement stmt = conn.createStatement();
		    	String sql = "select * from user";
//		    	ResultSet rs = stmt.executeQuery(sql);
		    	ResultSet rs = (new MysqlDBConnection()).queryForSet(sql);
		    	while (rs.next()) {
					String stemp = "";
		    		stemp += rs.getString(1);
		    		stemp += rs.getString(2);
		    		stemp += rs.getString(3);
		    		stemp += rs.getString(4);
					pwWriter.println(stemp);
				}
			} catch (Exception e) {
				// TODO: handle exception
				e.printStackTrace();
			} finally{
				
			}
			pwWriter.println("ni hao");
			pwWriter.println(EncryptComm.GetAccessTokenStr());
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
