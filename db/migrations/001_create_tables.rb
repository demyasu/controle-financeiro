Sequel.migration do
  change do
    create_table(:users) do
      String :email, primary_key: true
      String :username, null: false
      String :password_hash, null: false
      TrueClass :admin, default: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:transactions) do
      primary_key :id
      foreign_key :user_email, :users, type: String, null: false, key: [:email]
      Date :transaction_date
      String :description
      Float :amount, default: 0
      String :transaction_type
      String :category
      String :payment_method
      String :financing_type
      Integer :installments
      Date :due_date
      String :bank
      String :card_name
      String :status, default: 'Pendente'
      String :income_type
      String :paid_installments, default: '[]'
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:reg_tokens) do
      String :token, primary_key: true
      String :email, null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      TrueClass :used, default: false
    end

    create_table(:login_tokens) do
      String :token, primary_key: true
      String :email, null: false
      String :code
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      TrueClass :used, default: false
    end

    create_table(:app_metadata) do
      String :key, primary_key: true
      Integer :value, default: 0
    end
  end
end
