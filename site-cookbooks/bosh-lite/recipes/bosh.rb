%w(
  make
  libxslt-dev
  libyajl-dev
  genisoimage
  kpartx
  wamerican
  nginx
  libcurl4-openssl-dev
  redis-server
).each do |package_name|
  package package_name
end

include_recipe 'bosh-lite::rbenv'

include_recipe 'runit'

node.set['postgresql']['password']['postgres'] = 'postges'
#node.set['postgresql']['config']['data_directory'] = '/opt/bosh/db'
node.set['postgresql']['config']['port'] = 5432
node.set['postgresql']['config']['ssl'] = false
include_recipe 'postgresql::server'
include_recipe 'postgresql::ruby'

# Workaround for nats gem install
rbenv_gem "eventmachine" do
  version "0.12.10"
end

%w(pg nats).each do |gem|
  rbenv_gem gem
end

postgresql_database 'bosh' do
  connection ({:host => "127.0.0.1", :port => 5432, :username => 'postgres', :password => node['postgresql']['password']['postgres']})
  action :create
end

%w(bosh-director simple_blobstore_server bosh-monitor).each do |gem|
  rbenv_gem gem do
    version '>=1.5.0.pre.1113'
  end
end

rbenv_gem 'bosh_warden_cpi' do
  version '1.5.0.pre.48'
  source 'https://s3.amazonaws.com/bosh-jenkins-gems-warden/'
end

%w(config blobstore director db).each do |dir|
  directory "/opt/bosh/#{dir}" do
    owner 'vagrant'
    mode 0755
    action :create
    recursive true
  end
end

%w(bosh-monitor.yml simple_blobstore_server.yml).each do |config_file|
  cookbook_file "/opt/bosh/config/#{config_file}" do
    owner 'vagrant'
  end
end

template "/opt/bosh/config/director.yml" do
  source "director.yml.erb"
  mode 0755
  owner "vagrant"
  variables({
     :director_ip => node[:director_ip] || '192.168.50.4'
  })
end


execute 'migrate' do
  user 'vagrant'
  # UGLY HACK WARNING - the warden cpi isn't on the load path until we require something for it.  Not sure why.
  #
  command 'RUBYOPT="-r bosh/director -r cloud/warden/helpers" /opt/rbenv/shims/bosh-director-migrate -c /opt/bosh/config/director.yml'
end

cookbook_file '/etc/nginx/nginx.conf' do
  mode 0755
end

directory '/etc/nginx/ssl' do
  mode 0755
  action :create
end

execute 'create director ssl key and csr' do
  command 'openssl req -nodes -new -newkey rsa:1024 -out /etc/nginx/ssl/director.csr -keyout /etc/nginx/ssl/director.key -subj \'/O=Bosh/CN=*\''
end

execute 'self sign director ssl csr' do
  command 'openssl x509 -req -days 3650 -in /etc/nginx/ssl/director.csr -signkey /etc/nginx/ssl/director.key -out /etc/nginx/ssl/director.pem'
end

service 'nginx' do
  action :restart
end

%w(worker-0 worker-1 director).each do |service_name|
  runit_service service_name do
    default_logger true
    options({:user => 'root'})
  end
end

%w(blobstore bosh-monitor nats).each do |service_name|
  runit_service service_name do
    default_logger true
    options({:user => 'root'})
  end
end
