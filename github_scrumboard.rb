require 'prawn'
require 'octokit'
require 'highline/import'
require 'yaml'
require 'pry'


begin
  C = YAML::load(open("github_scrumboard.yml"))['default']
rescue StandardError
  abort "Couldn't find a configuration file!"
end


class UserStory
  attr_accessor :id, :title, :size, :priority, :text
  def initialize(issue)
    self.id = issue['number'].to_s
    self.title = issue['title'].to_s
    self.size = fish_for_size(issue['labels'])
    self.priority = fish_for_priority(issue['labels'])
    self.text = issue['body'].to_s
  end

  def fish_for_size(labels)
    fish_for(labels, /#{C['issues']['label']['prefix']['size']}(\d+)/)
  end

  def fish_for_priority(labels)
    fish_for(labels, /#{C['issues']['label']['prefix']['priority']}(\d+)/)
  end

  def fish_for(labels, regex)
    labels.each do |l|
      if l.name =~ regex
        return $1.to_i
      end
    end
    nil
  end

  def self.body(story)
    Proc.new do
      bounding_box [0, cursor], :width  => bounds.width do
        text_box story.text, :at => [bounds.left, bounds.top], :width => bounds.width
      end
    end
  end

  def self.header(story, height = 30)
    Proc.new do
      bounding_box [bounds.left, bounds.top], :width  => bounds.width, :height => height*1.25 do
        bounding_box [bounds.left, bounds.top], :width  => bounds.width, :height => height do
          split_width = 0.80 * bounds.width
          text_box "##{story.id} #{story.title}", :at => [bounds.left, bounds.top], :width => split_width, :height => height, :align => :left
          text_box story.priority_and_size, :at => [split_width, bounds.top], :width => (bounds.width - split_width), :height => height, :align => :right
        end
        stroke_horizontal_rule
      end
    end
  end

  def priority_and_size
    p = self.priority.nil? ? nil : "Priority: #{self.priority}"
    s = self.size.nil? ? nil : "Size: #{self.size}"
    [p,s].compact.join("\n")
  end

end

password = ask("Enter password: ") { |q| q.echo = false }

client = Octokit::Client.new(:login => C['github']['login'], :password => password)
puts "Getting issues from Github..."
issues = []
page = 0
begin
  page = page +1
  temp_issues = client.list_issues(C['github']['project'], :state => "open", :page => page)
  unless C['issues']['label']['filter'].empty?
    temp_issues.select! {|i| i['labels'].to_s =~ /#{C['issues']['label']['filter']}/}
  end
  issues.push(*temp_issues)
end while not temp_issues.empty?

stories = issues.collect do |issue|
  UserStory.new(issue)
end

def pagination(index, grid)
    j = (index % grid['columns'])
    i = (index / grid['rows']) % grid['columns']
    return [i, j]
end

def filled(index, grid)
  (((index + 1) % (grid['columns'] * grid['rows'])) == 0)
end

pdf = Prawn::Document.generate(C['file']['name'], C['page']) do
  font "Helvetica"
  define_grid(C['grid'])
  stories.each_with_index do |story, index|
    i,j = pagination(index, C['grid'])
    grid(i,j).bounding_box do
      instance_exec(&UserStory.header(story))
      instance_exec(&UserStory.body(story))
    end
    if filled(index, C['grid'])
      start_new_page
    end
  end
end

