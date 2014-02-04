# encoding: utf-8
require 'rubygems'
require 'bundler'
require 'sinatra'
require 'haml'
require 'data_mapper'
require 'keepass/password'
require 'bcrypt'
require 'warden'
require 'pony'
require 'json'
require 'sinatra/subdomain'
require 'net/http'
require 'uri'
require 'nokogiri'
require 'carrierwave'
require 'carrierwave/datamapper'

class Remzona24App < Sinatra::Base
  register Sinatra::Subdomain

  configure do
    enable :sessions, :logging

    # use Rack::Session::Cookie, secret: "rem_zona_24_ru_secret"

    Pony.options = {
      :from => 'noreply@remzona24.ru',
      :via => :smtp,
      :charset => 'utf-8',
      :via_options => {
        :address => 'smtp.gmail.com',
        :port => '587',
        :enable_starttls_auto => true,
        :user_name => 'sergey.rodionov@gmail.com',
        :password => 'Neverfoget1',
        :authentication => :login, # :plain, :login, :cram_md5, no auth by default
        :domain => "localhost.localdomain" # the HELO domain provided by the client to the server
      }
    }

    # datamaper
    DataMapper.setup(:default, 'postgres://sergey_rodionov:remzonapass@localhost/remzona')
    # DataMapper::Model.raise_on_save_failure = true

    class ImageUploader < CarrierWave::Uploader::Base
      include CarrierWave::MiniMagick
      storage :file
      permissions 0777
      def store_dir
        'uploads/images'
      end
      def cache_dir
        'uploads/tmp'
      end
      def extension_white_list
        %w(jpg jpeg gif png)
      end
      process :resize_to_fit => [1280, 1024]
      version :avatar64 do
        process :resize_to_fill => [64,64]
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
          :presence  => "Введите Ваш адрес электронной почты",
          :is_unique => "Данный адрес элект$ронной почты уже зарегистрирован",
          :format    => "Неверный формат адреса электронной почты"
        }
      property :domain, String, :unique => true, :format => /\w/, :length => 3..12,
        :messages => {
          :presence  => "Введите имя Вашей персональной страницы",
          :is_unique => "Указанная Вами страница уже зарегистрирована",
          :length => "Длина Вашей страницы должна быть от 3 до 12 символов",
          :format => "Название персональной страницы может содержать только латинские буквы, цифры или знак подчеркивания ('_')"
        }
      property :fullname, String, :length => 3..50,
        :messages => {
          :presence => "Введите информацию о контактном лице",
          :length => "Имя контактного лица должно быть от 3 и до 50 символов"
        }
      property :familyname, String, :length => 3..50,
        :messages => {
          :presence => "Введите Вашу фамилию",
          :length => "Фамилия должна быть от 3 и до 50 символов"
        }
      property :name, String, :length => 3..50,
        :messages => {
          :presence => "Введите Ваше имя",
          :length => "Имя должно быть от 3 и до 50 символов"
        }
      property :fathersname, String, :length => 3..50,
        :messages => {
          :presence => "Введите Ваше отчество",
          :length => "Отчество должно быть от 3 и до 50 символов"
        }
      property :mapx, Float
      property :mapy, Float    
      # property :location, String, :required => true,
      #   :messages => {
      #     :presence => "Выберите Ваш населенный пункт"
      #   }
      property :password, BCryptHash, :required => true
      property :created_at, DateTime
      property :lastlogon, DateTime
      property :status, Integer     #0 - active; 1-overdue
      property :description, Text,
        :messages => {
          :length => "Описание заявки должно быть менее 65535 символов"
        }
      property :legalstatus, Integer
      mount_uploader :avatar, ImageUploader

      validates_presence_of :fullname, :if => lambda { |t| t.type == "User" }
      validates_presence_of :familyname, :name, :fathersname, :domain, :if => lambda { |t| t.type == "Master" }

      has n, :orders
      has n, :offers
      has n, :messages, :child_key => [:sender_id]
      has n, :usertaggings
      has n, :tags, :through => :usertaggings
      
      belongs_to :placement

      def authenticate(attempted_password)
        if self.password == attempted_password
          true
        else
          false
        end
      end
    end

    class Message
      include DataMapper::Resource

      property :id, Serial
      property :unread, Boolean
      property :text, Text, :required => true,
        :messages => {
          :presence => "Не указан текст сообщения"
        }
      property :date, DateTime, :required => true,
        :messages => {
          :presence => "Не указана дата сообщения"
        }

      has 1, :child, self, :child_key => [:parent_id]

      belongs_to :parent,  self, :required => false
      belongs_to :order
      belongs_to :sender, 'User'
      belongs_to :receiver, 'User'
    end

    class Order
      include DataMapper::Resource

      property :id, Serial
      property :title, String, :required => true, :length => 3..50,
        :messages => {
          :presence => "Введите заголовок заявки",
          :length => "Длина заголовка заявки должна быть от 3 и до 50 символов"
        }
      property :subject, Text, :required => true,
        :messages => {
          :presence => "Введите описание заявки",
          :length => "Описание заявки должно быть менее 65535 символов"
        }
      property :budget, Integer,
        :messages => {
          :format => "Бюджет должен быть численным значением"
        }
      # property :area, String
      # property :location, String
      property :fd, DateTime
      property :td, DateTime
      property :status, Integer
      property :views, Integer

      has n, :offers
      has n, :messages
      has n, :ordertaggings
      has n, :tags, :through => :ordertaggings
      has n, :orderimages

      belongs_to :user
      belongs_to :placement
    end

    class Tag
      include DataMapper::Resource

      property :id, Serial
      property :tag, String, :length => 3..50

      has n, :ordertaggings
      has n, :orders, :through => :ordertaggings
      has n, :usertaggings
      has n, :users, :through => :usertaggings
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
      property :budget, Integer,
        :messages => {
          :format => "Бюджет должен быть численным значением"
        }
      property :time, Integer
      property :nodetails, Integer
      property :fd, DateTime
      property :td, DateTime
      property :status, Integer   #0 - active; 1-overdue

      belongs_to :order
      belongs_to :user
    end

    DataMapper.finalize
    # DataMapper.auto_migrate!
    DataMapper.auto_upgrade!

    use Warden::Manager do |config|
      # config.default_strategies :password, action: 'auth/unauthenticated'
      config.failure_app = self
      config.serialize_into_session{|user| user.id }
      config.serialize_from_session{|id| User.get(id) }

      config.scope_defaults :default,
        strategies: [:password],
        action: 'auth/unauthenticated'
    end

    Warden::Manager.before_failure do |env,opts|
      env['REQUEST_METHOD'] = 'POST'
    end

    Warden::Strategies.add(:password) do
      def valid?
        params["email"] && params["password"]
      end

      def authenticate!
        user = User.first(:email => params["email"])
        if user.nil?
          fail!("Пользователь, с указанной электронной почтой, не зарегистрирован")
        elsif user.authenticate(params["password"])
          user.lastlogon = DateTime.now
          success!(user)
        else
          fail!("Could not log in")
        end
      end
    end

  end

  helpers do
    def current_user
      # @current_user ||= User.get(session[:user_id]) if session[:user_id]
      @current_user = env['warden'].user if env['warden'].authenticated?

    end
    
    def logged_in?
      current_user
    end
  end

  #*************************************************************************************************************
  subdomain :foo do
    get '/' do
      "render page for FOO"
    end
  end

  subdomain do
    get '/' do
      "render page for #{subdomain} subdomain"
    end
  end

  get '/' do
    # url = "http://geoip.elib.ru/cgi-bin/getdata.pl"
    # resp = Net::HTTP.get_response(URI.parse(url))
    # city = Nokogiri::Slop(resp.body).GeoIP.GeoAddr.Town.content
    # url = URI::encode("http://api.vk.com/method/database.getCities?v=5&country_id=1&count=1&q="+city)
    # resp = Net::HTTP.get_response(URI.parse(url))
    # puts "*******", JSON.parse(resp.body), "*******"
    @activelink = '/'
    if params[:page].nil?
      @offset = 0
      @current_page = 1
    else
      @offset = params[:page].to_i*10
      @current_page = params[:page].to_i
    end
    @orders_at_mainpage = Order.all(:fd.lte => DateTime.now, :td.gte => DateTime.now, :status => 0, :order => [ :fd.desc ], :offset => @offset, :limit => 10)
    @orders_at_mainpage_total = @orders_at_mainpage.count
    @total_pages = (@orders_at_mainpage_total/10.0).ceil
    @start_page  = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 10
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 10) > 0 ? (@end_page - 10) : 1
    end
    @pagination = @start_page..@end_page
    if !logged_in?
      if !session[:siteregionplaceholder]
        session[:siteregionplaceholder] = "Россия"
      end 
      haml :navbarbeforelogin, :layout => :cover do
        haml :promo
      end
    else
      haml :navbarafterlogin, :layout => :cover do
        haml :index
      end
    end
  end

  post '/' do
    @activelink = '/'
    if params[:page].nil?
      @offset = 0
      @current_page = 1
    else
      @offset = params[:page].to_i*10
      @current_page = params[:page].to_i
    end
    @orders_at_mainpage = Order.all(:fd.lte => DateTime.now, :td.gte => DateTime.now, :status => 0, :order => [ :fd.desc ], :offset => @offset, :limit => 10)
    @orders_at_mainpage_total = @orders_at_mainpage.count
    @total_pages = (@orders_at_mainpage_total/10.0).ceil
    @start_page = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 10
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 10) > 0 ? (@end_page - 10) : 1
    end
    @pagination = @start_page..@end_page
    session[:siteregion] = params[:siteregion]
    session[:sitearea] = params[:sitearea]
    session[:sitelocation] = params[:sitelocation]
    session[:siteregionplaceholder] = params[:sitelocation] + (params[:sitearea].size > 0 ? ", " + params[:sitearea] : "") + (params[:siteregion].size > 0 ? ", " + params[:siteregion] : "")
    if !logged_in?
      haml :navbarbeforelogin, :layout => :cover do
        haml :promo
      end
    else
      haml :navbarafterlogin, :layout => :cover do
        haml :index
      end
    end
  end

  get '/region/:region' do
    @activelink = '/region'
    if params[:page].nil?
      @offset = 0
      @current_page = 1
    else
      @offset = params[:page].to_i*10
      @current_page = params[:page].to_i
    end
    @orders_at_mainpage = Order.all(:placement => {:region => params[:region]}, :fd.lte => DateTime.now, :td.gte => DateTime.now, :status => 0, :order => [ :fd.desc ])
    @orders_at_mainpage_total = @orders_at_mainpage.count
    @total_pages = (@orders_at_mainpage_total/10.0).ceil
    @start_page  = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 10
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 10) > 0 ? (@end_page - 10) : 1
    end
    @pagination = @start_page..@end_page
    if !logged_in?
      haml :navbarbeforelogin, :layout => :cover do
        haml :promo
      end
    else
      haml :navbarafterlogin, :layout => :cover do
        haml :index
      end
    end
  end

  get '/area/:area' do
    @activelink = '/area'
    if params[:page].nil?
      @offset = 0
      @current_page = 1
    else
      @offset = params[:page].to_i*10
      @current_page = params[:page].to_i
    end
    @orders_at_mainpage = Order.all(:placement => {:area => params[:area]}, :fd.lte => DateTime.now, :td.gte => DateTime.now, :status => 0, :order => [ :fd.desc ])
    @orders_at_mainpage_total = @orders_at_mainpage.count
    @total_pages = (@orders_at_mainpage_total/10.0).ceil
    @start_page  = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 10
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 10) > 0 ? (@end_page - 10) : 1
    end
    @pagination = @start_page..@end_page
    if !logged_in?
      haml :navbarbeforelogin, :layout => :cover do
        haml :promo
      end
    else
      haml :navbarafterlogin, :layout => :cover do
        haml :index
      end
    end
  end

  get '/location/:location' do
    @activelink = '/location'
    if params[:page].nil?
      @offset = 0
      @current_page = 1
    else
      @offset = params[:page].to_i*10
      @current_page = params[:page].to_i
    end
    @orders_at_mainpage = Order.all(:placement => {:location => params[:location]}, :fd.lte => DateTime.now, :td.gte => DateTime.now, :status => 0, :order => [ :fd.desc ])
    @orders_at_mainpage_total = @orders_at_mainpage.count
    @total_pages = (@orders_at_mainpage_total/10.0).ceil
    @start_page  = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 10
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 10) > 0 ? (@end_page - 10) : 1
    end
    @pagination = @start_page..@end_page
    if !logged_in?
      haml :navbarbeforelogin, :layout => :cover do
        haml :promo
      end
    else
      haml :navbarafterlogin, :layout => :cover do
        haml :index
      end
    end
  end

  post '/reguser' do
    if params[:password] != params[:pass]
      session[:error] = "Ошибка при повторном вводе пароля. Пожалуйста, пройдите процедуру регистрации еще раз"
      redirect back
    end
    placement = Placement.first_or_new(
      :region => params[:region],
      :area => params[:area],
      :location => params[:locationtitle])
    if placement.save
      user = User.new(
        :email => params[:email],
        :type => "User",
        :fullname => params[:fullname],
        :created_at => DateTime.now,
        :password => params[:password],
        :placement => placement,
        :status => 0)
      if user.save
        session[:user_id] = user.id
        @msg = "Здравствуйте, " + user.fullname + "\nВы успешно зарегистрировались на сайте РемЗона24.ру" + "\n\nДля входа на сайт используйте Ваш логин (" + user.email + ") и пароль, указанный при регистрации.\n\nЭто уведомление создано и отправлено автоматически, отвечать на него не нужно.\n\n--\nС уважением, РемЗона24.ру"
        Pony.mail(:to => user.email, :subject => 'Регистрация на РемЗона24.ру', :body => @msg)
        env['warden'].authenticate!
        redirect '/profile'
      else
        session[:error] = user.errors.values.join("; ")
        redirect back
      end
    else
      session[:error] = placement.errors.values.join("; ")
      redirect back
    end
  end

  post '/regmaster' do
    if params[:password] != params[:pass]
      session[:error] = "Ошибка при повторном вводе пароля. Пожалуйста, пройдите процедуру регистрации еще раз"
      redirect back
    end
    placement = Placement.first_or_new(
      :region => params[:region],
      :area => params[:area],
      :location => params[:locationtitle])
    if placement.save
      user = User.new(
        :email => params[:email],
        :type => "Master",
        :familyname => params[:familyname],
        :name => params[:name],
        :fathersname => params[:fathersname],
        :created_at => DateTime.now,
        :password => params[:password],
        :placement => placement,
        :status => 0,
        :description => params[:description],
        :domain => params[:domain])
      if user.save
        session[:user_id] = user.id
        tagsstring = params[:tags]
        tagsstring.split(",").each do |t|
          tag = user.tags.first_or_create(:tag => t)
        end
        @msg = "Здравствуйте, " + user.name + " " + user.familyname + "\nВы успешно зарегистрировались на сайте РемЗона24.ру" + "\n\nДля входа на сайт используйте Ваш логин (" + user.email + ") и пароль, указанный при регистрации.\n\nЭто уведомление создано и отправлено автоматически, отвечать на него не нужно.\n\n--\nС уважением, РемЗона24.ру"
        Pony.mail(:to => user.email, :subject => 'Регистрация на РемЗона24.ру', :body => @msg)
        env['warden'].authenticate!
        redirect '/profile'
      else
        session[:error] = user.errors.values.join("; ")
        redirect back
      end
    else
      session[:error] = placement.errors.values.join("; ")
      redirect back
    end
  end

  post '/auth/login' do
    env['warden'].authenticate!
    redirect back
  end

  post '/auth/unauthenticated' do
    redirect '/'
  end

  get '/profile' do
    if logged_in?
      haml :navbarafterlogin, :layout => :cover do
        case @current_user.type
          when "User"
            @myactiveorders = Order.all(:user => current_user, :fd.lte => DateTime.now, :td.gte => DateTime.now, :status => 0, :order => [ :fd.desc ])
            @myclosedorders = Order.all(:user => current_user, :td.lt => DateTime.now, :order => [ :fd.desc ]) + Order.all(:user => current_user, :status.not => 0, :order => [ :fd.desc ])
            #@newoffers = Offer.count(:order_id => Order.all(:user => current_user))
            # @newoffers = Offer.all(:order_id=>Order.all(:user_id => 1))
            @newoffers = repository(:default).adapter.select('SELECT COUNT(*) FROM remzona24_app_offers WHERE order_id IN (SELECT id FROM remzona24_app_orders WHERE user_id = ?) AND unread = true;', current_user.id)

            puts "*********", @newoffers, "*********"
            haml :userprofile
          when "Master"
            @tags = []
            @current_user.tags.all.each do |t|
              @tags << t.tag
            end
            @tags = @tags.join(",")
            @myactiveoffers = Order.all(:offers => {:user => current_user}, :fd.lte => DateTime.now, :td.gte => DateTime.now, :status => 0, :order => [ :fd.desc ])
            @myclosedoffers = Order.all(:offers => {:user => current_user}, :td.lt => DateTime.now, :order => [ :fd.desc ]) + Order.all(:offers => {:user => current_user}, :status.not => 0, :order => [ :fd.desc ])
            haml :masterprofile
        end
      end
    else
      redirect '/'
    end
  end

  get '/user/:id' do
    begin
      @user = User.get(params[:id])
    rescue
      session[:error] = "Пользователь не найден"
      redirect back
    end
    if logged_in?
      haml :navbarafterlogin, :layout => :cover do
        case @user.type
          when "User"
            haml :userview
          when "Master"
            @tags = []
            @user.tags.all.each do |t|
              @tags << t.tag
            end
            @tags = @tags.join(",")
            haml :masterview
        end
      end
    else
      haml :navbarbeforelogin, :layout => :cover do
        case @user.type
          when "User"
            haml :userview
          when "Master"
            @tags = []
            @user.tags.all.each do |t|
              @tags << t.tag
            end
            @tags = @tags.join(",")
            haml :masterview
        end
      end
    end
  end

  post '/updateprofile' do
    current_user
    placement = Placement.first_or_new(
      :region => params[:region],
      :area => params[:area],
      :location => params[:locationtitle])
    if placement.save
      case @current_user.type
      when "Master"
        begin
          @current_user.update(:name => params[:name], :fathersname => params[:fathersname], :familyname => params[:familyname], :description => params[:description], :phone => params[:phone], :email => params[:email], :placement => placement)
          @current_user.update(:avatar => params[:avatar])
          oldtags = @current_user.usertaggings
          oldtags.each {|ot| ot.destroy }
          tagsstring = params[:tags]
          puts tagsstring
          tagsstring.split(",").each do |t|
            tag = @current_user.tags.first_or_create(:tag => t)
          end
        rescue
          session[:error] = @current_user.errors.values.join("; ")
          redirect back
        end
      when "User"
        begin
          @current_user.update(:avatar => params[:avatar], :fullname => params[:fullname], :email => params[:email], :placement => placement)
        rescue
          session[:error] = @current_user.errors.values.join("; ")
          redirect back
        end
      end
    else
      session[:error] = placement.errors.values.join("; ")
      redirect back
    end
    redirect back
  end

  post '/changepassword' do
    if logged_in?
      if @current_user.password != params[:oldpass]
        session[:error] = "Неправильно указан старый пароль. Пожалуйста, попробуйте сменить пароль еще раз"
        @messagetodisplay = "Неправильно указан старый пароль. Пожалуйста, попробуйте сменить пароль еще раз"
        redirect back
      end
      if params[:newpass1] != params[:newpass2]
        session[:error] = "Ошибка при повторном вводе нового пароля. Пожалуйста, попробуйте сменить пароль еще раз"
        @messagetodisplay = "Ошибка при повторном вводе нового пароля. Пожалуйста, попробуйте сменить пароль еще раз"
        redirect back
      end
      @current_user.update(:password => params[:newpass1])
      haml :navbarafterlogin, :layout => :cover do
        haml :profile
      end
    else
      redirect back
    end
  end

  post '/setmap' do
    current_user
    @current_user.update(:mapx => params[:mapx].to_f, :mapy => params[:mapy].to_f)
    redirect back
  end

  post '/uploadavatar' do
    current_user
    @current_user.update(:avatar => params[:avatar])
    redirect back
  end

  get '/regsuccess' do
    if logged_in?
      haml :navbarafterlogin, :layout => :cover do
        haml :regsuccess
      end
    else
      session[:error] = "К сожалению, при входе в систему возникла ошибка. Пожалуйста, попробуйте войти еще раз"
      redirect back
    end
  end

  get '/neworder' do
    if !logged_in?
      redirect '/'
    else
      haml :navbarafterlogin, :layout => :cover do
        haml :neworder
      end
    end
  end

  post '/addorder' do
    if params[:lifetime].to_i > 0
      td = Time.now+params[:lifetime].to_i*86400
    else
      td = Time.new(3000,1,1)
    end

    if params[:budgettype] == "1"
      budget = -1
    else
      budget = params[:budget]
    end

    order = Order.new(
      :user => current_user,
      :title => params[:title],
      :subject => params[:subject],
      :budget => budget,
      :fd => Time.now,
      :td => td,
      :status => 0,
      :views => 0,
      :placement_id => @current_user.placement_id)

    if order.save
      tagsstring = params[:tags]
      tagsstring.split(",").each do |t|
        tag = order.tags.first_or_create(:tag => t)
      end
      params[:photos].each do |image|
        oi = Orderimage.create(:order => order, :image => image)
      end
      redirect '/profile'
    else
      session[:error] = order.errors.values.join("; ")
      redirect back
    end
  end

  post '/addoffer/:order' do
    current_user
    order = Order.get(params[:order])
    budget = params[:budget]
    nodetails = 0
    td = Time.now+params[:lifetime].to_i*86400
    if params[:nodetails] == "on"
      budget = -1
      nodetails = 1
      td = Time.new(3000,1,1)
    end
    offer = Offer.new(
      :user => current_user,
      :order => order,
      :subject => params[:subject],
      :budget => budget,
      :time => params[:time],
      :fd => Time.now,
      :td => td,
      :nodetails => nodetails,
      :status => 0,
      :unread => true)
    if offer.save
      redirect back
    else
      session[:error] = offer.errors.values.join("; ")
      redirect back
    end
  end

  post '/addquestion/:order' do
    current_user
    order = Order.get(params[:order])
    message = Message.new(
      :sender => current_user,
      :receiver => order.user,
      :order => order,
      :unread => true,
      :text => params[:question],
      :date => DateTime.now
    )
    if message.save
      redirect back
    else
      session[:error] = message.errors.values.join("; ")
      redirect back
    end
  end

  get '/order/:order' do
    begin
      @order = Order.get(params[:order])
    rescue
      session[:error] = "Заявка не существует"
      redirect back
    end
    @tags = []
    @order.tags.all.each do |t|
      @tags << t.tag
    end
    @tags = @tags.join(', ')
    views = @order.views + 1
    @order.update(:views => views)
    @photos = Orderimage.all(:order_id => params[:order].to_i)

    @offers = Offer.all(:order_id => params[:order].to_i)
    @offers.each do |o|
      if o.td < DateTime.now
        o.update(:status => 1)
      end
    end

    @questions = Message.all(:order_id => params[:order].to_i)

    if !logged_in?
      haml :navbarbeforelogin, :layout => :cover do
        haml :orderdetails
      end
    else
      haml :navbarafterlogin, :layout => :cover do
        haml :orderdetails
      end
    end
  end

  post '/closeorder/:order' do
    if !logged_in?
      haml :navbarbeforelogin, :layout => :cover do
        redirect '/'
      end
    else
      haml :navbarafterlogin, :layout => :cover do
        order = Order.get(params[:order])
        if order.user != current_user
          session[:error_message] = "У Вас нет прав на закрытие заявки"
          haml :error
        else
          order.update(:status => 1, :td => Time.now)
          redirect back
        end
      end
    end
  end

    post '/delorder/:order' do
    if !logged_in?
      haml :navbarbeforelogin, :layout => :cover do
        redirect '/'
      end
    else
      haml :navbarafterlogin, :layout => :cover do
        order = Order.get(params[:order])
        if order.user != current_user
          session[:error_message] = "У Вас нет прав на удаление заявки"
          haml :error
        else
          order.destroy
          redirect back
        end
      end
    end
  end

  get '/offer/:id' do
    begin
      @offer = Offer.get(params[:id])
      if @offer.fd < DateTime.now
        @offer.update(:status => 1)
      end
      @offer.update(:unread => false)
    rescue
      session[:error] = "Предложения не существует"
      redirect back
    end
    if !logged_in?
      haml :navbarbeforelogin, :layout => :cover do
        haml :offerdetails
      end
    else
      haml :navbarafterlogin, :layout => :cover do
        haml :offerdetails
      end
    end
  end

  get '/ajax/tags.json' do
    # tags = Tag.all
    # jsontags = []
    # tags.each do |t|
    #   jsontags << t.tag
    # end
    # JSON.generate(jsontags)

    @tags = Tag.all
    @tagslist = @tags.map do |u|
      { :id => u.id, :tag => u.tag }
    end

    json = { :tags => @tagslist }.to_json
    json
  end

  get '/hidemsg' do
    session[:error] = nil
    redirect back
  end

  # get '/error' do
  #   @error_message = session[:error]
  #   if !logged_in?
  #     haml :navbarbeforelogin, :layout => :cover do
  #       haml :error
  #     end
  #   else
  #     haml :navbarafterlogin, :layout => :cover do
  #       haml :error
  #     end
  #   end
  # end

  ["/auth/sign_out/?", "/auth/signout/?", "/auth/log_out/?", "/auth/logout/?"].each do |path|
    get path do
      env['warden'].raw_session.inspect
      env['warden'].logout
      session[:user_id] = nil
      redirect '/'
    end
  end

end

Remzona24App.run!