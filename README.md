# gocd-business-continuity-test

## Pre-Requisites
* Java
* Ruby
* Rake
* Bundler
* Docker Engine(If running on Linux distros)
* Docker Machine(If running on Mac/Windows, this script tested with Docker on Mac)


**Setup**

1. Checkout https://github.com/gocd/docker-gocd-server and https://github.com/gocd/docker-gocd-agent in same workspace as this repository
2. Run `cd  gocd-business-continuity-test`
3. Run `bundle exec rake`

## License

```plain
Copyright 2017 ThoughtWorks, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
