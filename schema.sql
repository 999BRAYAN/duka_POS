-- duka_pos Version 3 — MySQL schema.
--
-- The same twelve tables as Version 1's Drift schema (schema version 7),
-- translated to MySQL. Money and quantities are DECIMAL(15,4) rather than
-- floating point so a total can never pick up a stray 0.30000000000000004.
-- Run through `python init_db.py`, which creates the database first.

CREATE TABLE IF NOT EXISTS users (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  uuid          CHAR(36)     NOT NULL UNIQUE,
  username      VARCHAR(100) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  full_name     VARCHAR(200) NOT NULL,
  role          VARCHAR(20)  NOT NULL,            -- admin, manager, cashier
  is_active     TINYINT(1)   NOT NULL DEFAULT 1,
  -- Only one user may ever hold the 'manager' role at a time. v1 enforced
  -- that with a partial unique index; MySQL has none, so this generated
  -- column is 1 for a manager and NULL for everyone else, and a UNIQUE index
  -- over it (NULLs never collide) gives the identical guarantee no matter
  -- which code path inserts or updates a user.
  manager_slot  TINYINT GENERATED ALWAYS AS (CASE WHEN role = 'manager' THEN 1 ELSE NULL END) STORED,
  created_at    DATETIME(3)  NOT NULL,
  updated_at    DATETIME(3)  NULL,
  UNIQUE KEY idx_single_manager (manager_slot)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS categories (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  uuid        CHAR(36)     NOT NULL UNIQUE,
  name        VARCHAR(200) NOT NULL,
  description TEXT         NULL,
  created_at  DATETIME(3)  NOT NULL,
  updated_at  DATETIME(3)  NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS products (
  id                INT AUTO_INCREMENT PRIMARY KEY,
  uuid              CHAR(36)      NOT NULL UNIQUE,
  sku               VARCHAR(100)  NULL,
  barcode           VARCHAR(100)  NULL,
  name              VARCHAR(255)  NOT NULL,
  description       TEXT          NULL,
  category_id       INT           NULL,
  unit              VARCHAR(30)   NOT NULL DEFAULT 'pcs',
  cost_price        DECIMAL(15,4) NOT NULL DEFAULT 0,
  selling_price     DECIMAL(15,4) NOT NULL DEFAULT 0,
  min_selling_price DECIMAL(15,4) NOT NULL DEFAULT 0,
  -- Never written directly outside stock.record_movement — that's the only
  -- path allowed to change this column, so every change is backed by an
  -- audit-trail row in stock_movements.
  stock             DECIMAL(15,4) NOT NULL DEFAULT 0,
  reorder_level     DECIMAL(15,4) NOT NULL DEFAULT 0,
  is_active         TINYINT(1)    NOT NULL DEFAULT 1,
  created_at        DATETIME(3)   NOT NULL,
  updated_at        DATETIME(3)   NULL,
  KEY idx_products_barcode (barcode),
  CONSTRAINT fk_products_category FOREIGN KEY (category_id) REFERENCES categories (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS customers (
  id              INT AUTO_INCREMENT PRIMARY KEY,
  uuid            CHAR(36)      NOT NULL UNIQUE,
  name            VARCHAR(255)  NOT NULL,
  phone           VARCHAR(50)   NULL,
  email           VARCHAR(255)  NULL,
  address         TEXT          NULL,
  credit_limit    DECIMAL(15,4) NOT NULL DEFAULT 0,
  current_balance DECIMAL(15,4) NOT NULL DEFAULT 0,
  -- The single seeded walk-in customer (see init_db.py) — always
  -- credit_limit 0, and the customer service refuses to edit this row
  -- regardless of who's asking.
  is_walk_in      TINYINT(1)    NOT NULL DEFAULT 0,
  created_at      DATETIME(3)   NOT NULL,
  updated_at      DATETIME(3)   NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS suppliers (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  uuid       CHAR(36)      NOT NULL UNIQUE,
  name       VARCHAR(255)  NOT NULL,
  phone      VARCHAR(50)   NULL,
  email      VARCHAR(255)  NULL,
  address    TEXT          NULL,
  -- Outstanding amount owed to this supplier, accumulated by receive_stock
  -- whenever a receipt isn't paid in full.
  balance    DECIMAL(15,4) NOT NULL DEFAULT 0,
  created_at DATETIME(3)   NOT NULL,
  updated_at DATETIME(3)   NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sales (
  id                INT AUTO_INCREMENT PRIMARY KEY,
  uuid              CHAR(36)      NOT NULL UNIQUE,
  invoice_number    VARCHAR(30)   NOT NULL UNIQUE,
  customer_id       INT           NULL,
  user_id           INT           NOT NULL,
  subtotal          DECIMAL(15,4) NOT NULL DEFAULT 0,
  discount          DECIMAL(15,4) NOT NULL DEFAULT 0,
  tax               DECIMAL(15,4) NOT NULL DEFAULT 0,
  total             DECIMAL(15,4) NOT NULL DEFAULT 0,
  amount_paid       DECIMAL(15,4) NOT NULL DEFAULT 0,
  payment_method    VARCHAR(20)   NOT NULL,       -- cash, mpesa, card, credit
  -- Cost of goods sold and gross profit, computed once from each line's
  -- cost-at-sale-time and persisted rather than recomputed later.
  cogs              DECIMAL(15,4) NOT NULL DEFAULT 0,
  gross_profit      DECIMAL(15,4) NOT NULL DEFAULT 0,
  status            VARCHAR(20)   NOT NULL DEFAULT 'completed',   -- completed, void, refunded
  void_reason       TEXT          NULL,
  voided_by_user_id INT           NULL,
  created_at        DATETIME(3)   NOT NULL,
  updated_at        DATETIME(3)   NULL,
  KEY idx_sales_created (created_at),
  CONSTRAINT fk_sales_customer FOREIGN KEY (customer_id)       REFERENCES customers (id),
  CONSTRAINT fk_sales_user     FOREIGN KEY (user_id)           REFERENCES users (id),
  CONSTRAINT fk_sales_voider   FOREIGN KEY (voided_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sale_items (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  uuid       CHAR(36)      NOT NULL UNIQUE,
  sale_id    INT           NOT NULL,
  product_id INT           NOT NULL,
  quantity   DECIMAL(15,4) NOT NULL,
  unit_price DECIMAL(15,4) NOT NULL,
  discount   DECIMAL(15,4) NOT NULL DEFAULT 0,
  total      DECIMAL(15,4) NOT NULL,
  created_at DATETIME(3)   NOT NULL,
  updated_at DATETIME(3)   NULL,
  CONSTRAINT fk_sale_items_sale    FOREIGN KEY (sale_id)    REFERENCES sales (id),
  CONSTRAINT fk_sale_items_product FOREIGN KEY (product_id) REFERENCES products (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS purchases (
  id               INT AUTO_INCREMENT PRIMARY KEY,
  uuid             CHAR(36)      NOT NULL UNIQUE,
  reference_number VARCHAR(100)  NULL,
  supplier_id      INT           NOT NULL,
  user_id          INT           NOT NULL,
  subtotal         DECIMAL(15,4) NOT NULL DEFAULT 0,
  discount         DECIMAL(15,4) NOT NULL DEFAULT 0,
  tax              DECIMAL(15,4) NOT NULL DEFAULT 0,
  total            DECIMAL(15,4) NOT NULL DEFAULT 0,
  amount_paid      DECIMAL(15,4) NOT NULL DEFAULT 0,
  status           VARCHAR(20)   NOT NULL DEFAULT 'pending',    -- pending, received, cancelled
  payment_status   VARCHAR(20)   NOT NULL DEFAULT 'unpaid',     -- paid, partial, unpaid
  created_at       DATETIME(3)   NOT NULL,
  updated_at       DATETIME(3)   NULL,
  CONSTRAINT fk_purchases_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers (id),
  CONSTRAINT fk_purchases_user     FOREIGN KEY (user_id)     REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS purchase_items (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  uuid        CHAR(36)      NOT NULL UNIQUE,
  purchase_id INT           NOT NULL,
  product_id  INT           NOT NULL,
  quantity    DECIMAL(15,4) NOT NULL,
  unit_cost   DECIMAL(15,4) NOT NULL,
  total       DECIMAL(15,4) NOT NULL,
  created_at  DATETIME(3)   NOT NULL,
  updated_at  DATETIME(3)   NULL,
  CONSTRAINT fk_purchase_items_purchase FOREIGN KEY (purchase_id) REFERENCES purchases (id),
  CONSTRAINT fk_purchase_items_product  FOREIGN KEY (product_id)  REFERENCES products (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS stock_movements (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  uuid       CHAR(36)      NOT NULL UNIQUE,
  product_id INT           NOT NULL,
  type       VARCHAR(20)   NOT NULL,              -- SALE, PURCHASE, RETURN, ADJUSTMENT
  -- The signed delta actually applied to stock: negative for a SALE,
  -- positive for PURCHASE / RETURN.
  quantity   DECIMAL(15,4) NOT NULL,
  -- Cost per unit at the time of this movement; nullable because it isn't
  -- always known (e.g. a plain stock-count ADJUSTMENT).
  unit_cost  DECIMAL(15,4) NULL,
  reference  VARCHAR(100)  NULL,
  notes      TEXT          NULL,
  user_id    INT           NULL,
  created_at DATETIME(3)   NOT NULL,
  updated_at DATETIME(3)   NULL,
  KEY idx_stock_movements_created (created_at),
  CONSTRAINT fk_stock_movements_product FOREIGN KEY (product_id) REFERENCES products (id),
  CONSTRAINT fk_stock_movements_user    FOREIGN KEY (user_id)    REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS credit_transactions (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  uuid          CHAR(36)      NOT NULL UNIQUE,
  customer_id   INT           NOT NULL,
  sale_id       INT           NULL,
  -- CHARGE (a sale left a balance owing), PAYMENT (money collected),
  -- REVERSAL (a charged sale was voided). CHARGE increases the balance;
  -- PAYMENT and REVERSAL decrease it.
  type          VARCHAR(20)   NOT NULL,
  amount        DECIMAL(15,4) NOT NULL,
  balance_after DECIMAL(15,4) NOT NULL,
  -- How a PAYMENT was taken (cash, mpesa, card). Null for CHARGE rows.
  method        VARCHAR(20)   NULL,
  notes         TEXT          NULL,
  created_at    DATETIME(3)   NOT NULL,
  updated_at    DATETIME(3)   NULL,
  CONSTRAINT fk_credit_customer FOREIGN KEY (customer_id) REFERENCES customers (id),
  CONSTRAINT fk_credit_sale     FOREIGN KEY (sale_id)     REFERENCES sales (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS expenses (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  uuid        CHAR(36)      NOT NULL UNIQUE,
  category    VARCHAR(100)  NOT NULL,
  description TEXT          NOT NULL,
  amount      DECIMAL(15,4) NOT NULL,
  user_id     INT           NULL,
  created_at  DATETIME(3)   NOT NULL,
  updated_at  DATETIME(3)   NULL,
  KEY idx_expenses_created (created_at),
  CONSTRAINT fk_expenses_user FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
