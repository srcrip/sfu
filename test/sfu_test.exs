defmodule SFUTest do
  use ExUnit.Case
  doctest SFU

  test "greets the world" do
    assert SFU.hello() == :world
  end
end
