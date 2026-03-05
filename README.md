# Secure Banking Management System

A full-stack DBMS based banking application that simulates core banking operations such as deposits, withdrawals, transfers and transaction logging.

## Technologies Used
- Python (Flask)
- MySQL
- HTML
- CSS

## Features
- Customer login system
- Admin dashboard
- Deposit money
- Withdraw money
- Transfer funds
- Transaction history
- Audit logging
- Stored procedures
- Database triggers
- ACID transaction support

## Database Design
The system includes the following tables:
- Customer
- Account
- Transaction_Log
- AuditLog
- AdminUser

The database follows **3NF normalization** and enforces referential integrity using foreign keys.

## Stored Procedures
- sp_deposit
- sp_withdraw
- sp_transfer

These procedures ensure secure financial transactions.

## Security Features
- Password hashing
- Session-based authentication
- Row-level locking using SELECT FOR UPDATE
- Audit logging for balance updates

## System Architecture
The application follows a **3-tier architecture**:

Frontend → HTML/CSS  
Backend → Flask  
Database → MySQL

## How to Run the Project

1 Install MySQL  
2 Import the database
