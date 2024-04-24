require 'sqlite3'
require 'sinatra'

require_relative './hello'

File.delete("sample.db") if File.exist?("sample.db")

db = SQLite3::Database.new "sample.db"

rows = db.execute <<-SQL
  create table numbers (
    name varchar(30),
    val int
  );
SQL

{
  "one" => 1,
  "two" => 2,
}.each do |pair|
  db.execute "insert into numbers values ( ?, ? )", pair
end

set :bind, '0.0.0.0'

get '/' do
  rows = db.execute 'select * from numbers;'
  rows.to_s
end

get '/hello' do
  Hello::World
end
