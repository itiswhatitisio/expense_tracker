require 'sinatra'
require 'sinatra/reloader'
require 'sinatra/content_for'
require 'tilt/erubis'
require 'date'

def error_for_name(item, group, type)
  if !(1..250).cover? item.size
    "#{type}  has #{item.size} characters. The name must be between 1 and 250 characters."
  elsif group.map(&:name).any? { |existing_item| existing_item == item }
    "#{type} name must be unique."
  end
end

def error_for_future_date(date)
  current_date = DateTime.now
  return 'The date cannot be in the future.' if Date.parse(date) > current_date
end

class Transaction
  attr_accessor :date, :amount, :category, :note, :type

  def initialize(transaction_details)
    p transaction_details
    @date = transaction_details[:date]
    @amount = if transaction_details[:type] == 'expense'
                -transaction_details[:amount].to_f
              else
                transaction_details[:amount].to_f
              end
    @category = transaction_details[:category]
    @note = transaction_details[:note]
    @type = transaction_details[:type]
  end
end

class Account
  attr_accessor :name, :balance, :transactions

  def initialize(name, balance)
    @name = name
    @balance = balance
    @transactions = []
  end

  def add(transaction)
    @transactions.push(transaction)
    update_balance(transaction)
  end

  def update_balance(transaction)
    @balance += transaction.amount
  end
end

class Category
  attr_accessor :name, :type, :icon

  def initialize(icon, name, type)
    @icon = icon
    @name = name
    @type = type
  end
end

configure do
  enable :sessions
  set :session_secret, 'secret'
end

before do
  session[:transactions] ||= []
  # session[:errors] ||= []
  # session[:success] ||= []
end

helpers do
  def generate_dropdown(options)
    select_options = []
    options.each do |option|
      select_options << "<option value='#{option.name}'>#{option.name}</option>"
    end
    select_options.join('')
  end

  def set_default_accounts
    session[:accounts] = []

    session[:accounts] << Account.new('💵 Cash', 0)
    session[:accounts] << Account.new('🏦 Checking', 0)
  end

  def set_default_categories
    session[:categories] = []

    default_categories = [{icon: '🍉 ', name: 'Groceries', type: 'expense'},{icon: '🍽️ ', name: 'Eating out', type: 'expense'},
                          {icon: '🏠', name: 'House', type: 'expense'}, {icon: '🔌 ', name: 'Utilities', type: 'expense'},
                          {icon: '👔 ', name: 'Salary', type: 'income'}, {icon: '💸', name: 'Freelance', type: 'income'}]

    default_categories.each do |category|
      session[:categories] << Category.new(category[:icon], category[:name], category[:type])
    end
  end
end

get '/' do
  p session
  set_default_categories if session[:categories].nil?
  set_default_accounts if session[:accounts].nil?
  session[:errors] = [] if session[:errors].nil?
  session[:success] = [] if session[:success].nil?

  if !session[:categories].nil?
  @expense_categories = session[:categories].select { |category| category.type == 'expense' }
  @income_categories = session[:categories].select { |category| category.type == 'income' }
  end

  current_month = Date.today.strftime('%Y-%B')
  @this_month_spend = session[:accounts].map(&:transactions)
                                        .flatten
                                        .select { |transaction| DateTime.parse(transaction.date).strftime('%Y-%B') == current_month && transaction.type == 'expense'}
                                        .reduce(0) { |sum, transaction| sum + transaction.amount }

  erb :homepage, layout: :layout
end

post '/transactions/add' do
  p session
    session[:last_amount] = params[:amount]

  if params[:date].empty?
    session[:last_amount] = params[:amount]
    session[:errors] = []
    session[:errors] << 'The date cannot be empty.'
  end

  if error_for_future_date(params[:date])
    session[:last_amount] = params[:amount]
    session[:last_amount] = params[:amount].to_i
    if session[:errors]
      session[:errors] << error_for_future_date(params[:date])
    else
      session[:errors]
      session[:errors] << error_for_future_date(params[:date]) 
    end
  end

  if params[:amount].empty?
    session[:errors] << 'The amount cannot be empty.'
    session[:last_date] = params[:date] if !params[:date].empty? || !params[:date].nil? && error_for_future_date(params[:date])
  end

  if session[:errors].nil? || session[:errors].empty?
    selected_account = session[:accounts].find { |account| account.name == params[:account]}
    selected_account.add(Transaction.new(params))
    p session
    session[:success] = 'The transcation has been added successfully.'
    session[:last_date] = ''
    session[:last_amount] = ''
  end

  redirect '/'
end

get '/transactions' do
  case params[:period]
  when 'this_month'
    current_month = Date.today.strftime('%Y-%B')
    current_month_expenses = session[:expenses].select do |expense|
      DateTime.parse(expense.date).strftime('%Y-%B') == current_month
    end
    current_month_expenses
  when 'previous_month'
    previous_month = Date.today.prev_month.strftime('%Y-%B')
    previous_month_expenses = session[:expenses].select do |expense|
      DateTime.parse(expense.date).strftime('%Y-%B') == previous_month
    end
    previous_month_expenses
    end
  erb :transactions, layout: :layout
end

get '/income' do
  if !session[:categories].nil?
  @expense_categories = session[:categories].select { |category| category.type == 'expense' }
  @income_categories = session[:categories].select { |category| category.type == 'income' }
  end
  erb :income, layout: :layout
end

get '/categories' do
  erb :categories, layout: :layout
end

post '/category/add' do
  error = error_for_name(params[:category], session[:categories], 'Category')
  if error
    session[:errors] << error
  else
    session[:categories] << Category.new(params[:category], params[:type])
    session[:success] = 'A new category has been created.'
  end

  redirect '/categories'
end

get '/accounts' do
  erb :accounts, layout: :layout
end

get '/transactions' do
  erb :transactions, layout: :layout
end

post '/account/add' do
  error = error_for_name(params[:name], session[:accounts], 'Account')

  if error
    session[:errors] << error
  else
    session[:accounts] << Account.new(params[:name], params[:balance].to_i)
    session[:success] = 'Account has been added succsessfully.'
  end

  redirect '/accounts'
end

get '/edit/account/:id' do
  @id = params[:id].to_i
  erb :edit_account, layout: :layout
end

post '/edit/account/:id' do
  @id = params[:id].to_i
  session[:accounts][@id].name = params[:name]
  session[:accounts][@id].balance = params[:balance]
  redirect '/accounts'
end

post '/delete/account/:id' do
  @id = params[:id].to_i
  name = session[:categories][@id].name
  session[:accounts].delete_at(@id)
  session[:success] = "Account #{name} has been successfully deleted."
  redirect '/accounts'
end

get '/edit/category/:id' do
  @id = params[:id].to_i
  erb :edit_category, layout: :edit_category
end

post '/edit/category/:id' do
  @id = params[:id].to_i
  session[:categories][@id].name = params[:name]
  redirect '/categories'
end

post '/delete/category/:id' do
  @id = params[:id].to_i
  name = session[:categories][@id].name
  session[:categories].delete_at(@id)
  session[:success] << "Category #{name} has been successfully deleted."
  redirect '/categories'
end
