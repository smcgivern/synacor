def ackermann(c)
  values = {}

  0.upto(32768) do |b|
    values[[0, b]] = b.succ % 32768
  end

  1.upto(4) do |a|
    values[[a, 0]] = values[[a - 1, c]]

    1.upto(32768) do |b|
      next if a == 4 && b > 1

      values[[a, b]] = values[[a.pred, values[[a, b.pred]]]]
    end
  end

  values[[4, 1]]
end

0.upto(32768) do |c|
  if ackermann(c) == 6
    p c
    break
  end
end
