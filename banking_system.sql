DROP DATABASE IF EXISTS banking_system;
CREATE DATABASE banking_system;
USE banking_system;

-- TABLES

CREATE TABLE Customer (
  CustomerID INT AUTO_INCREMENT PRIMARY KEY,
  FirstName VARCHAR(100) NOT NULL,
  LastName VARCHAR(100),
  Email VARCHAR(150) UNIQUE,
  Phone VARCHAR(20),
  AadharNumber VARCHAR(20) UNIQUE,
  PanNumber VARCHAR(20) UNIQUE,
  PasswordHash VARCHAR(255) NOT NULL,
  CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Account (
  AccountID INT AUTO_INCREMENT PRIMARY KEY,
  CustomerID INT NOT NULL,
  AccountNumber VARCHAR(20) UNIQUE,
  AccountType VARCHAR(20),
  Balance DECIMAL(15,2) DEFAULT 0,
  IsActive BOOLEAN DEFAULT TRUE,
  CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID) ON DELETE CASCADE
);

CREATE TABLE Transaction_Log (
  TransactionID INT AUTO_INCREMENT PRIMARY KEY,
  AccountID INT NOT NULL,
  RelatedAccountID INT,
  Type VARCHAR(20),
  Amount DECIMAL(15,2),
  BalanceBefore DECIMAL(15,2),
  BalanceAfter DECIMAL(15,2),
  CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  Remarks TEXT,
  FOREIGN KEY (AccountID) REFERENCES Account(AccountID) ON DELETE CASCADE
);

CREATE TABLE AuditLog (
  AuditID INT AUTO_INCREMENT PRIMARY KEY,
  AccountID INT,
  OldBalance DECIMAL(15,2),
  NewBalance DECIMAL(15,2),
  ChangedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  ChangedBy VARCHAR(50),
  Reason TEXT
);

CREATE TABLE AdminUser (
  AdminID INT AUTO_INCREMENT PRIMARY KEY,
  Username VARCHAR(100) UNIQUE NOT NULL,
  PasswordHash VARCHAR(255) NOT NULL,
  CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- SAMPLE DATA

INSERT INTO AdminUser (Username, PasswordHash) 
VALUES ('admin', SHA2('admin123',256));

INSERT INTO Customer (FirstName, LastName, Email, Phone, PasswordHash)
VALUES 
('Swastik', 'Sangwan', 'swastik@example.com', '9999999999', SHA2('pass123',256)),
('Rohan', 'Lal', 'rohan@example.com', '8888888888', SHA2('pass123',256));

INSERT INTO Account (CustomerID, AccountNumber, AccountType, Balance)
VALUES 
(1, 'AC000001', 'SAVINGS', 1000.00),
(2, 'AC000002', 'SAVINGS', 500.00);


-- stored procedure

-- deposit
DROP PROCEDURE IF EXISTS sp_deposit;
DELIMITER //
CREATE PROCEDURE sp_deposit(IN accId INT, IN amt DECIMAL(15,2), IN username VARCHAR(50))
BEGIN
  DECLARE oldBal, newBal DECIMAL(15,2);

  IF amt <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deposit amount must be greater than zero';
  END IF;

  START TRANSACTION;
  SELECT Balance INTO oldBal FROM Account WHERE AccountID = accId FOR UPDATE;

  SET newBal = oldBal + amt;
  UPDATE Account SET Balance = newBal WHERE AccountID = accId;

  INSERT INTO Transaction_Log(AccountID, Type, Amount, BalanceBefore, BalanceAfter, Remarks)
  VALUES (accId, 'DEPOSIT', amt, oldBal, newBal, 'Deposit successful');

  INSERT INTO AuditLog(AccountID, OldBalance, NewBalance, ChangedBy, Reason)
  VALUES (accId, oldBal, newBal, username, 'Deposit');

  COMMIT;
END //
DELIMITER ;

-- withdraw
DROP PROCEDURE IF EXISTS sp_withdraw;
DELIMITER //
CREATE PROCEDURE sp_withdraw(IN accId INT, IN amt DECIMAL(15,2), IN username VARCHAR(50))
BEGIN
  DECLARE oldBal, newBal DECIMAL(15,2);

  IF amt <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Withdrawal amount must be greater than zero';
  END IF;

  START TRANSACTION;
  SELECT Balance INTO oldBal FROM Account WHERE AccountID = accId FOR UPDATE;

  IF oldBal < amt THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance';
  END IF;

  SET newBal = oldBal - amt;
  UPDATE Account SET Balance = newBal WHERE AccountID = accId;

  INSERT INTO Transaction_Log(AccountID, Type, Amount, BalanceBefore, BalanceAfter, Remarks)
  VALUES (accId, 'WITHDRAW', amt, oldBal, newBal, 'Withdrawal successful');

  INSERT INTO AuditLog(AccountID, OldBalance, NewBalance, ChangedBy, Reason)
  VALUES (accId, oldBal, newBal, username, 'Withdraw');

  COMMIT;
END //
DELIMITER ;

-- transfer
DROP PROCEDURE IF EXISTS sp_transfer;
DELIMITER //
CREATE PROCEDURE sp_transfer(IN src INT, IN tgt INT, IN amt DECIMAL(15,2), IN username VARCHAR(50))
BEGIN
  DECLARE srcBal, tgtBal DECIMAL(15,2);
  DECLARE srcAcc VARCHAR(30);
  DECLARE tgtAcc VARCHAR(30);

  IF amt <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transfer amount must be greater than zero';
  END IF;

  SELECT AccountNumber INTO srcAcc FROM Account WHERE AccountID = src;
  SELECT AccountNumber INTO tgtAcc FROM Account WHERE AccountID = tgt;

  START TRANSACTION;

  SELECT Balance INTO srcBal FROM Account WHERE AccountID = src FOR UPDATE;
  SELECT Balance INTO tgtBal FROM Account WHERE AccountID = tgt FOR UPDATE;

  IF srcBal < amt THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient funds for transfer';
  END IF;

  UPDATE Account SET Balance = srcBal - amt WHERE AccountID = src;
  UPDATE Account SET Balance = tgtBal + amt WHERE AccountID = tgt;

  INSERT INTO Transaction_Log(AccountID, RelatedAccountID, Type, Amount, BalanceBefore, BalanceAfter, Remarks)
  VALUES (src, tgt, 'TRANSFER_DEBIT', amt, srcBal, srcBal - amt, CONCAT('Transferred to account ', tgtAcc));

  INSERT INTO Transaction_Log(AccountID, RelatedAccountID, Type, Amount, BalanceBefore, BalanceAfter, Remarks)
  VALUES (tgt, src, 'TRANSFER_CREDIT', amt, tgtBal, tgtBal + amt, CONCAT('Received from account ', srcAcc));

  INSERT INTO AuditLog(AccountID, OldBalance, NewBalance, ChangedBy, Reason)
  VALUES (src, srcBal, srcBal - amt, username, 'Transfer Debit'),
         (tgt, tgtBal, tgtBal + amt, username, 'Transfer Credit');

  COMMIT;
END //
DELIMITER ;


-- trigger

DROP TRIGGER IF EXISTS trg_account_update_audit;
DELIMITER //
CREATE TRIGGER trg_account_update_audit
AFTER UPDATE ON Account
FOR EACH ROW
BEGIN
  IF OLD.Balance <> NEW.Balance AND @skip_audit IS NULL THEN
    INSERT INTO AuditLog(AccountID, OldBalance, NewBalance, ChangedBy, Reason)
    VALUES (NEW.AccountID, OLD.Balance, NEW.Balance, USER(), 'Manual update via trigger');
  END IF;
END //
DELIMITER ;
