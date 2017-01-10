require 'sourcify'

class Object

  def fail_unless &blk
    _fail_if(blk.source) { !blk.call }
  end

  def fail_if &blk
    _fail_if(blk.source) { blk.call }
  end

  def _fail_if(err_msg, &condition)
    if condition.call
      raise(RuntimeError, err_msg)
    end
  end

end
