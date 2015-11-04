package com.winel.test;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

public class MysqlDBConnection {
	private final String driverClass = "com.mysql.jdbc.Driver";
	private final String url="jdbc:mysql://123.57.229.6:3306/mysql";//数据库主机地址以及数据库名     
	private final String user="root";//MySQ帐号     
	private final String password="ZHoiun89825";//MYSQL密码
	//
	private Statement stmt;
	
	/**
	 * void init connection
	 * @throws ClassNotFoundException 
	 * @throws IllegalAccessException 
	 * @throws InstantiationException 
	 */
	private void initDB(){
		try {
			Connection conn = null;
			Class.forName(driverClass).newInstance();
			conn = DriverManager.getConnection(url, user, password);
			stmt = conn.createStatement();
		} catch (SQLException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		} catch (InstantiationException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		} catch (IllegalAccessException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		} catch (ClassNotFoundException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		}
	}
	
	/**
	 * @param SqlText
	 * @return ResultSet
	 * @throws SQLException 
	 */ 
	public ResultSet queryForSet(String sql) throws SQLException{
		initDB();
		
		return stmt.executeQuery(sql);
	}
	
	public static String testabc(){
		return "";
	}

}
