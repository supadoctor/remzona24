# encoding: utf-8

# setting for local DB @ home's notebook
# DataMapper.setup(:default, 'postgres://sergey_rodionov:remzonapass@localhost/remzona') 

# settings for nitrous.io
# DataMapper.setup(:default, 'postgres://action:action@localhost/remzona24')

# settings for VPS

configure :test, :development do
  DataMapper.setup(:default, 'postgres://postgres:postgres@localhost/remzona24test')
end

configure :production do
  DataMapper.setup(:default, 'postgres://postgres:postgres@localhost/remzona24')
end

DataMapper::Model.raise_on_save_failure = true

class ImageUploader < CarrierWave::Uploader::Base
  include CarrierWave::MiniMagick
  storage :file
  permissions 0666
  directory_permissions 0777
  def store_dir
    'uploads/images'
  end
  def cache_dir
    'uploads/tmp'
  end
  def extension_white_list
    %w(jpg jpeg gif png)
  end
  process :resize_to_limit => [1280, 1024]
  version :avatar64 do
    process :resize_to_fill => [64,64]
  end
end

class PricelistUploader < CarrierWave::Uploader::Base
  storage :file
  permissions 0666
  directory_permissions 0777
  def store_dir
    'uploads/pricelists'
  end
  def cache_dir
    'uploads/tmp'
  end
  def extension_white_list
    %w(doc docx xls xlsx pdf txt)
  end
end


class Orderimage
  include DataMapper::Resource
  property :id, Serial
  mount_uploader :image, ImageUploader
  belongs_to :order
end

class User
  include DataMapper::Resource
  include BCrypt

  property :id, Serial
  property :type, String
  property :phone, String, :format => /^((8|\+7)\d{10}$)/,
    :messages => {
      :format    => "Неверный формат мобильного номера. Номер должен начинатся с +7 или 8 и затем содержать 10 цифр"
    }
  property :email, String, :unique => true, :required => true,
    :format   => :email_address,
    :messages => {
      :presence  => "Введите адрес электронной почты",
      :is_unique => "Данный адрес электронной почты уже зарегистрирован",
      :format    => "Неверный формат электронной почты"
    }
  #property :domain, String, :required => false, :unique => true, :format => /\w/, :length => 3..12,
  #  :messages => {
  #    :is_unique => "Указанная вами страница уже зарегистрирована",
  #    :format    => "Название персональной страницы может содержать только латинские буквы, цифры или знак подчеркивания ('_')",      
  #    :length    => "Длина вашей страницы должна быть от 3 до 12 символов"
  #  }
  property :fullname, String, :length => 2..50, :format => /^[а-яА-ЯёЁa-zA-Z- ]+$/,
    :messages => {
      :length    => "Полное имя контактного лица должно быть от 2 и до 50 символов",
      :format    => "Полное имя может содержать только буквы и пробел"
    }
  property :familyname, String, :length => 2..50, :format => /^[а-яА-ЯёЁa-zA-Z]+$/,
    :messages => {
      :length    => "Фамилия должна быть от 2 и до 50 символов",
      :format    => "Фамилия может содержать только буквы"
    }
  property :name, String, :length => 2..50, :format => /^[а-яА-ЯёЁa-zA-Z]+$/,
    :messages => {
      :length    => "Имя должно быть от 2 и до 50 символов",
      :format    => "Имя может содержать только буквы"
    }
  property :fathersname, String, :length => 50, :format => /^[а-яА-ЯёЁa-zA-Z]+$/,
    :messages => {
      :length    => "Отчество должно быть не более 50 символов",
      :format    => "Отчество может содержать только буквы"
    }
  property :mapx, Float
  property :mapy, Float
  property :password, BCryptHash, :required => true
  property :created_at, DateTime
  property :lastlogon, DateTime
  property :status, Integer     #0 - active;
  property :description, Text,
    :messages => {
      :length => "Описание должно быть менее 65535 символов"
    }
  property :legalstatus, Integer
  property :adstatus, Integer #0 - no ads, 1 - only vertical ad blosk, 2 - only horizontal ad block, 3 - all ad

  mount_uploader :avatar, ImageUploader
  mount_uploader :pricelist, PricelistUploader

  validates_presence_of :fullname, :if => lambda { |t| t.type == "User" },
    :message => "Введите полное имя контактного лица"
  validates_presence_of :familyname, :name, :if => lambda { |t| t.type == "Master" },
    :message => "Введите ФИО"

  has n, :orders
  has n, :offers
  has n, :messages, :child_key => [:sender_id]
  has n, :usertaggings
  has n, :tags, :through => :usertaggings
  #has n, :taggings
  #has n, :tags, :through => :taggings
  has 1, :profile
  has n, :contracts, :child_key => [ :customer_id ]
  has n, :contractors, self, :through => :contracts, :via => :contractor
  has n, :reviews, :child_key => [ :user_id ]
  
  belongs_to :placement, :required => false
  
  validates_presence_of :placement_id, :if => lambda { |t| t.type == "Master" || t.type == "User" },
    :message => "Не указан населенный пункт"
  
  def authenticate(attempted_password)
    if self.password == attempted_password
      true
    else
      false
    end
  end
  
  def displayedname
    if self.type == "User" || self.type == "Admin"
      self.fullname
    elsif self.type == "Master"
      if !self.fathersname.nil?
        self.name + " " + self.fathersname + " " + self.familyname
      else
        self.name + " " + self.familyname
      end
    end
  end
end

class Contract
  include DataMapper::Resource
  
  property :id, Serial
  property :date, DateTime
  has 1, :review
  belongs_to :order
  belongs_to :customer, 'User', :key => true
  belongs_to :contractor, 'User', :key => true
end

class Profile
  include DataMapper::Resource
  
  property :id, Serial
  property :showemail, Boolean
  property :showphone, Boolean
  property :sendmessagestoemail, Boolean
  
  belongs_to :user
end

class Message
  include DataMapper::Resource

  property :id, Serial
  property :unread, Boolean, :default  => true
  property :archived, Boolean, :default  => false
  property :subject, String, :required => false, :length => 3..50,
    :messages => {
      :length => "Длина темы сообщения должна быть от 3 до 50 символов"
    }
  property :text, Text, :required => true,
    :messages => {
      :presence => "Не указан текст сообщения"
    }
  property :date, DateTime, :required => true,
    :messages => {
      :presence => "Не указана дата сообщения"
    }
  property :type, String

  has 1, :child, self, :child_key => [:parent_id]
  has 1, :parent, self, :child_key => [:child_id]

  belongs_to :parent,  self, :required => false
  belongs_to :child, self, :required => false
  belongs_to :order, :required => false
  belongs_to :offer, :required => false
  belongs_to :sender, 'User'
  belongs_to :receiver, 'User'
end

class Order
  include DataMapper::Resource

  property :id, Serial
  property :title, String, :required => true, :length => 3..50,
    :messages => {
      :presence => "Введите заголовок заявки",
      :length => "Длина заголовка заявки должна быть от 3 до 50 символов"
    }
  property :subject, Text, :required => true,
    :messages => {
      :presence => "Введите описание заявки",
      :length => "Описание заявки должно быть менее 65535 символов"
    }
  property :budget, Integer, :required => false, :format  => /^-?\d+$/,
    :messages => {
      :format => "Бюджет должен быть целым численным значением"
    }
  # property :area, String
  # property :location, String
  property :fd, DateTime, :required => true
  property :td, DateTime, :required => true
  property :status, Integer    #0-active, 1-stopped, 2-deleted, 3-wait for contractor's accept
  property :views, Integer

  has n, :offers
  has n, :messages
  has n, :ordertaggings
  has n, :tags, :through => :ordertaggings
  #has n, :taggings
  #has n, :tags, :through => :taggings
  has n, :orderimages
  has 1, :vehicle
  has 1, :contract

  belongs_to :user, :required => true
  belongs_to :placement, :required => true
end

class Tag
  include DataMapper::Resource

  property :id, Serial
  property :tag, String, :length => 3..50

  has n, :ordertaggings
  has n, :orders, :through => :ordertaggings
  has n, :usertaggings
  has n, :users, :through => :usertaggings
  #has n, :taggings
  #has n, :orders, :through => :taggings
  #has n, :users, :through => :taggings
end

class Ordertagging
  include DataMapper::Resource

  belongs_to :tag, :key => true
  belongs_to :order, :key => true
end

class Usertagging
  include DataMapper::Resource

  belongs_to :tag, :key => true
  belongs_to :user, :key => true
end

#class Tagging
#  include DataMapper::Resource
#
#  belongs_to :tag, :key => true
#  belongs_to :order, :key => true
#  belongs_to :user, :key => true
#end

class Placement
  include DataMapper::Resource

  property :id, Serial
  property :location, String, :required => true,
    :messages => {
      :presence => "Населенный пункт не найден. Уточните наименование населенного пункта"
    }
  property :area, String
  property :region, String

  has n, :users
  has n, :orders
end

class Offer
  include DataMapper::Resource

  property :id, Serial
  property :unread, Boolean
  property :subject, Text, :required => true,
    :messages => {
      :presence => "Введите описание предложения",
      :length => "Описание предложения должно быть менее 65535 символов"
    }
  property :budget, Integer, :required => false, :format  => /^-?\d+$/,
    :messages => {
      :format => "Бюджет должен быть целым численным значением"
    }
  property :time, Integer
  property :nodetails, Integer
  property :fd, DateTime
  property :td, DateTime
  property :status, Integer   #0 - active; 1-overdue; 2-wait for contractor's accept; 3- acceptwork; 4-refused by contractor
  
  has n, :messages
  belongs_to :order
  belongs_to :user
end

class ResetPasswords
  include DataMapper::Resource
  include BCrypt
  
  property :id, Serial
  property :email, String, :required => true, :format => :email_address,
    :messages => {
      :format => "Не корректный формат электронной почты",
      :presence => "Обязательно укажите адрес электронной почты"
    }
  property :myhash, BCryptHash
  property :td, DateTime
end

class Vehicle
  include DataMapper::Resource
  
  property :id, Serial
  property :make, String, :required => true,
    :messages => {
      :presence => "Введите марку автомобиля"
    }
  property :mdl, String, :required => true,
    :messages => {
      :presence => "Введете модель автомобиля"
    }
  property :year, Integer, :required => false
  property :VIN, String, :required => false, :length => 17,
    :messages => {
      :length    => "VIN должен состоять из 17 символов"
    }
  
  belongs_to :order
end

class Review
  include DataMapper::Resource
  
  property :id, Serial
  property :rating, Integer, :required => true,
    :messages => {
      :presence => "Не указан рейтинг"
    }
  property :text, Text
  property :date, DateTime
  
  belongs_to :author, 'User', :key => true
  belongs_to :user
  belongs_to :contract
end

DataMapper.finalize
#DataMapper.auto_migrate! #recreate all table
DataMapper.auto_upgrade! #try to upgrade models

if User.count == 0
  admin = User.new(
    :email => "admin@remzona24.ru",
    :type => "Admin",
    :fullname => "Администрация Портала",
    :created_at => DateTime.now,
    :password => "Neverfoget1",
    :status => 0,
    :profile => Profile.new(:showemail => false, :showphone => false, :sendmessagestoemail => false))
  begin
    admin.save
    puts "ADMIN WAS CREATED!\n"
  rescue
    puts admin.errors.values.join("; ")
  end
end