from flask import Flask, render_template, request, redirect, session, url_for, flash
import mysql.connector
import hashlib
import os
from dotenv import load_dotenv  

load_dotenv()  


app = Flask(__name__)
app.secret_key = "super_secret_key_12345"

db = mysql.connector.connect(
    host=os.environ.get('DB_HOST', 'localhost'),
    user=os.environ.get('DB_USER', 'root'),
    password=os.environ.get('DB_PASSWORD', ''),
    database=os.environ.get('DB_NAME', 'banking_system')
)
cursor = db.cursor(dictionary=True)

# customer routes
@app.route('/landing')
def landing():
    return render_template('index.html')

@app.route('/')
def home():
    print("🧠 Current session content:", session)
    if 'user' in session:
        user = session['user']

        cursor.execute("""
            SELECT SUM(Balance) AS total_balance 
            FROM Account 
            WHERE CustomerID = %s
        """, (user['CustomerID'],))
        result = cursor.fetchone()
        total_balance = result['total_balance'] if result and result['total_balance'] is not None else 0.00

        return render_template('dashboard.html', user=user, total_balance=total_balance)
    
    return render_template('index.html')



@app.route('/login', methods=['GET'])
def show_login_page():
    return render_template('login.html')

@app.route('/login', methods=['POST'])
def login():
    email = request.form['email']
    pwd = hashlib.sha256(request.form['password'].encode()).hexdigest()
    cursor.execute("SELECT * FROM Customer WHERE Email=%s AND PasswordHash=%s", (email, pwd))
    user = cursor.fetchone()
    if user:
        session['user'] = user
        print("✅ Logged in user stored in session:", session['user'])
        return redirect('/')
    
    flash("Invalid credentials")
    return redirect('/login')



@app.route('/logout')
def logout():
    session.clear()
    return redirect('/')

@app.route('/deposit', methods=['POST'])
def deposit():
    if 'user' not in session:
        return redirect('/')
    acc_id = request.form['account_id']
    amt = request.form['amount']
    user = session['user']['FirstName']
    try:
        cursor.callproc('sp_deposit', (int(acc_id), float(amt), user))
        db.commit()
        flash("Deposit successful")
    except Exception as e:
        db.rollback()
        flash("Error: " + str(e))
    return redirect('/')

@app.route('/withdraw', methods=['POST'])
def withdraw():
    if 'user' not in session:
        return redirect('/')
    acc_id = request.form['account_id']
    amt = request.form['amount']
    user = session['user']['FirstName']
    try:
        cursor.callproc('sp_withdraw', (int(acc_id), float(amt), user))
        db.commit()
        flash("Withdrawal successful")
    except Exception as e:
        db.rollback()
        flash("Error: " + str(e))
    return redirect('/')

@app.route('/transfer', methods=['POST'])
def transfer():
    if 'user' not in session:
        return redirect('/')
    src = request.form['source']
    tgt = request.form['target']
    amt = request.form['amount']
    user = session['user']['FirstName']
    try:
        cursor.callproc('sp_transfer', (int(src), int(tgt), float(amt), user))
        db.commit()
        flash("Transfer successful")
    except Exception as e:
        db.rollback()
        flash("Error: " + str(e))
    return redirect('/')

@app.route('/transactions')
def transactions():
    if 'user' not in session:
        return redirect('/')
    user = session['user']

    cursor.execute("""
        SELECT 
            t.Type,
            t.Amount,
            t.BalanceBefore,
            t.BalanceAfter,
            t.CreatedAt,
            t.Remarks,
            a.AccountNumber AS AccountNumber,
            ra.AccountNumber AS RelatedAccount
        FROM Transaction_Log t
        JOIN Account a ON t.AccountID = a.AccountID
        LEFT JOIN Account ra ON t.RelatedAccountID = ra.AccountID
        WHERE a.CustomerID = %s
        ORDER BY t.CreatedAt DESC
    """, (user['CustomerID'],))
    
    txns = cursor.fetchall()
    return render_template('transactions.html', txns=txns)


# admin routes
@app.route('/admin')
def admin_login_page():
    if 'admin' in session:
        return redirect('/admin/dashboard')
    return render_template('admin_login.html')

@app.route('/admin/login', methods=['POST'])
def admin_login():
    uname = request.form['username']
    pwd = hashlib.sha256(request.form['password'].encode()).hexdigest()
    cursor.execute("SELECT * FROM AdminUser WHERE Username=%s AND PasswordHash=%s", (uname, pwd))
    admin = cursor.fetchone()
    if admin:
        session['admin'] = admin
        return redirect('/admin/dashboard')
    flash("Invalid admin credentials")
    return redirect('/admin')


@app.route('/admin/logout')
def admin_logout():
    session.pop('admin', None)
    return redirect('/admin')

@app.route('/admin/dashboard')
def admin_dashboard():
    if 'admin' not in session:
        return redirect('/admin')
    cursor.execute("SELECT COUNT(*) as total_customers FROM Customer")
    total_cust = cursor.fetchone()['total_customers']
    cursor.execute("SELECT COUNT(*) as total_accounts FROM Account")
    total_acc = cursor.fetchone()['total_accounts']
    return render_template('admin_dashboard.html', total_cust=total_cust, total_acc=total_acc)

#CRUD Customers
@app.route('/admin/customers')
def admin_customers():
    if 'admin' not in session:
        return redirect('/admin')
    cursor.execute("SELECT * FROM Customer")
    data = cursor.fetchall()
    return render_template('admin_customers.html', customers=data)

@app.route('/admin/customers/add', methods=['POST'])
def add_customer():
    if 'admin' not in session:
        return redirect('/admin')
    fn = request.form['fname']
    ln = request.form.get('lname', '')
    em = request.form['email']
    ph = request.form.get('phone', '')
    pwd = request.form['password']
    hash_pwd = hashlib.sha256(pwd.encode()).hexdigest()
    cursor.execute("INSERT INTO Customer (FirstName, LastName, Email, Phone, PasswordHash) VALUES (%s,%s,%s,%s,%s)",
                   (fn, ln, em, ph, hash_pwd))
    db.commit()
    return redirect('/admin/customers')

@app.route('/admin/customers/delete/<int:id>')
def delete_customer(id):
    if 'admin' not in session:
        return redirect('/admin')
    cursor.execute("DELETE FROM Customer WHERE CustomerID=%s", (id,))
    db.commit()
    return redirect('/admin/customers')

#CRUD Accounts
@app.route('/admin/accounts')
def admin_accounts():
    if 'admin' not in session:
        return redirect('/admin')
    cursor.execute("SELECT A.*, C.FirstName, C.LastName FROM Account A JOIN Customer C ON A.CustomerID=C.CustomerID")
    accs = cursor.fetchall()
    return render_template('admin_accounts.html', accounts=accs)

@app.route('/admin/accounts/add', methods=['POST'])
def add_account():
    if 'admin' not in session:
        return redirect('/admin')
    cid = request.form['customer_id']
    typ = request.form['type']
    cursor.execute("INSERT INTO Account (CustomerID, AccountNumber, AccountType, Balance) VALUES (%s, CONCAT('AC', LPAD(FLOOR(RAND()*999999),6,'0')), %s, 0)", (cid, typ))
    db.commit()
    return redirect('/admin/accounts')

@app.route('/admin/accounts/delete/<int:id>')
def delete_account(id):
    if 'admin' not in session:
        return redirect('/admin')
    cursor.execute("DELETE FROM Account WHERE AccountID=%s", (id,))
    db.commit()
    return redirect('/admin/accounts')

#Logs
@app.route('/admin/transactions')
def admin_txn_log():
    if 'admin' not in session:
        return redirect('/admin')
    cursor.execute("SELECT * FROM Transaction_Log ORDER BY CreatedAt DESC")
    data = cursor.fetchall()
    return render_template('admin_transactions.html', txns=data)

@app.route('/admin/audit')
def admin_audit_log():
    if 'admin' not in session:
        return redirect('/admin')
    cursor.execute("SELECT * FROM AuditLog ORDER BY ChangedAt DESC")
    data = cursor.fetchall()
    return render_template('admin_audit.html', logs=data)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=True)
