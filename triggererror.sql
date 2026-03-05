USE banking_system;

DROP PROCEDURE IF EXISTS sp_deposit;
DROP PROCEDURE IF EXISTS sp_withdraw;
DROP PROCEDURE IF EXISTS sp_transfer;


DROP TRIGGER IF EXISTS trg_account_update_audit;


DELIMITER //
CREATE PROCEDURE sp_deposit(IN accId INT, IN amt DECIMAL(15,2), IN username VARCHAR(50))
BEGIN
  DECLARE oldBal, newBal DECIMAL(15,2);

  IF amt <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deposit amount must be greater than zero';
  END IF;

  SET @skip_audit = 1;

  START TRANSACTION;
  SELECT Balance INTO oldBal FROM Account WHERE AccountID = accId FOR UPDATE;

  SET newBal = oldBal + amt;
  UPDATE Account SET Balance = newBal WHERE AccountID = accId;

  INSERT INTO Transaction_Log(AccountID, Type, Amount, BalanceBefore, BalanceAfter, Remarks)
  VALUES (accId, 'DEPOSIT', amt, oldBal, newBal, 'Deposit successful');

  INSERT INTO AuditLog(AccountID, OldBalance, NewBalance, ChangedBy, Reason)
  VALUES (accId, oldBal, newBal, username, 'Deposit');

  COMMIT;

  SET @skip_audit = NULL;
END //
DELIMITER ;


DELIMITER //
CREATE PROCEDURE sp_withdraw(IN accId INT, IN amt DECIMAL(15,2), IN username VARCHAR(50))
BEGIN
  DECLARE oldBal, newBal DECIMAL(15,2);

  IF amt <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Withdrawal amount must be greater than zero';
  END IF;

  SET @skip_audit = 1;

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

  SET @skip_audit = NULL;
END //
DELIMITER ;


DELIMITER //
CREATE PROCEDURE sp_transfer(IN src INT, IN tgt INT, IN amt DECIMAL(15,2), IN username VARCHAR(50))
BEGIN
  DECLARE srcBal, tgtBal DECIMAL(15,2);
  DECLARE srcAcc VARCHAR(30);
  DECLARE tgtAcc VARCHAR(30);

  IF amt <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transfer amount must be greater than zero';
  END IF;

  SET @skip_audit = 1;

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

  SET @skip_audit = NULL;
END //
DELIMITER ;


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
